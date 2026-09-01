defmodule Botica.Flags.PersistenceTest do
  @moduledoc """
  Tests for `Botica.Flags.Persistence` and the Disk JSON adapter.

  These tests use a temp file per test so they never touch the real
  `~/.botica/flags.json`.
  """

  use ExUnit.Case, async: false

  alias Botica.Flags
  alias Botica.Flags.Flag
  alias Botica.Flags.Persistence
  alias Botica.Flags.Persistence.Disk
  alias Botica.Flags.Store

  setup do
    # Isolate from the user's real flags file and from other tests.
    tmp_dir = Path.join(System.tmp_dir!(), "botica_flags_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    path = Path.join(tmp_dir, "flags.json")

    Application.put_env(:botica, :flags_persistence,
      adapter: Disk,
      opts: [path: path]
    )

    Store.table() |> :ets.delete_all_objects()

    on_exit(fn ->
      Application.put_env(:botica, :flags_persistence, [])
      File.rm_rf!(tmp_dir)
    end)

    %{path: path}
  end

  describe "Disk adapter" do
    test "save_flag/1 writes a JSON document that load_all/1 can read back", %{path: path} do
      flag = Flag.new(:persist_roundtrip, default: true, description: "roundtrip")

      assert :ok = Disk.save_flag(flag)
      assert File.exists?(path)

      assert {:ok, [loaded]} = Disk.load_all()
      assert loaded.name == :persist_roundtrip
      assert loaded.enabled == flag.enabled
      assert loaded.default == flag.default
      assert loaded.description == "roundtrip"
      assert DateTime.compare(loaded.created_at, flag.created_at) == :eq
      assert DateTime.compare(loaded.updated_at, flag.updated_at) == :eq
    end

    test "save_flag/1 round-trips percentage rollout maps", %{path: path} do
      flag = Flag.new(:persist_rollout_pct, default: false, rollout: %{type: :percentage, value: 25})
      :ok = Disk.save_flag(flag)

      assert {:ok, [loaded]} = Disk.load_all()
      assert loaded.rollout == %{type: :percentage, value: 25}
    end

    test "save_flag/1 round-trips user_list and attribute rollouts", %{path: path} do
      user_flag = Flag.new(:persist_users, default: false, rollout: %{type: :user_list, users: ["lorenzo", "ana"]})
      attr_flag = Flag.new(:persist_attr, default: false, rollout: %{type: :attribute, key: "tenant", values: ["acme"]})

      :ok = Disk.save_flag(user_flag)
      :ok = Disk.save_flag(attr_flag)

      assert {:ok, flags} = Disk.load_all()
      users = Enum.find(flags, &(&1.name == :persist_users))
      attr = Enum.find(flags, &(&1.name == :persist_attr))
      assert users.rollout == %{type: :user_list, users: ["lorenzo", "ana"]}
      assert attr.rollout == %{type: :attribute, key: "tenant", values: ["acme"]}
    end

    test "delete_flag/1 removes the flag from the JSON document", %{path: path} do
      flag = Flag.new(:persist_delete_me, default: true)
      :ok = Disk.save_flag(flag)
      assert {:ok, [_]} = Disk.load_all()

      assert :ok = Disk.delete_flag(:persist_delete_me)
      assert {:ok, []} = Disk.load_all()
    end

    test "load_all/1 returns empty list when file does not exist" do
      assert {:ok, []} = Disk.load_all()
    end

    test "load_all/1 returns error on malformed JSON", %{path: path} do
      File.write!(path, "not-json{")
      assert {:error, {:decode, _}} = Disk.load_all()
    end

    test "load_all/1 returns error when root is not an object", %{path: path} do
      File.write!(path, "[1,2,3]")
      assert {:error, {:malformed, _}} = Disk.load_all()
    end

    test "load_all/1 handles unknown rollout types defensively", %{path: path} do
      File.write!(path, Jason.encode!(%{"weird" => %{"rollout" => %{"type" => "bogus"}}}))
      assert {:error, :invalid_data} = Disk.load_all()
    end

    test "save_flag/1 fails cleanly when path directory does not exist" do
      Application.put_env(:botica, :flags_persistence,
        adapter: Disk,
        opts: [path: "/nonexistent_dir_xyz/flags.json"]
      )

      flag = Flag.new(:persist_bad_path, default: true)
      assert {:error, _} = Disk.save_flag(flag)
    end
  end

  describe "Store integration" do
    test "flags survive a Store restart through the disk adapter", %{path: path} do
      # 1. Define flags in the running store (persists to disk).
      Flags.define(:persist_survive_1, default: true)
      Flags.define(:persist_survive_2, default: false, rollout: 40)
      Flags.enable(:persist_survive_2)

      # Give the asynchronous Writer a moment to flush both writes.
      wait_for_flags(path, [:persist_survive_1, :persist_survive_2])

      # 2. Restart the whole application (simulates app restart).
      restart_app()

      # 3. Flags must be back from disk, with values preserved.
      assert {:ok, %Flag{enabled: true}} = Flags.get(:persist_survive_1)
      assert {:ok, %Flag{enabled: true, rollout: 40}} = Flags.get(:persist_survive_2)
    end

    test "deleted flags do not come back after restart", %{path: path} do
      Flags.define(:persist_delete_restart, default: true)
      wait_for_flags(path, [:persist_delete_restart])

      Flags.delete(:persist_delete_restart)
      wait_for_absence(path, :persist_delete_restart)

      restart_app()

      assert :error = Flags.get(:persist_delete_restart)
    end

    test "config defaults only apply to flags not persisted", %{path: path} do
      # Pre-write a flag directly via the adapter, bypassing the Store,
      # then boot the Store: the persisted value must win over config.
      persisted = Flag.new(:persist_defaults_win, default: true, enabled: true)
      :ok = Disk.save_flag(persisted)

      Application.put_env(:botica, :flags, [
        persist_defaults_win: [default: false]
      ])

      on_exit(fn -> Application.delete_env(:botica, :flags) end)

      restart_app()

      assert {:ok, %Flag{enabled: true}} = Flags.get(:persist_defaults_win)
    end
  end

  describe "configured/0" do
    test "defaults to Disk adapter with empty opts" do
      Application.put_env(:botica, :flags_persistence, [])
      assert {Botica.Flags.Persistence.Disk, []} = Persistence.configured()
    end

    test "reads adapter and opts from config" do
      Application.put_env(:botica, :flags_persistence, adapter: Disk, opts: [path: "/tmp/x.json"])
      assert {Disk, [path: "/tmp/x.json"]} = Persistence.configured()
    end

    test "enabled?/0 is false when adapter is false" do
      Application.put_env(:botica, :flags_persistence, adapter: false)
      refute Persistence.enabled?()
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Polls the JSON file until it contains all the given flag names
  # (the Writer flushes asynchronously).
  defp wait_for_flags(path, names, attempts \\ 100) do
    names_str = Enum.map(names, &Atom.to_string/1)

    if file_has_names?(path, names_str) do
      :ok
    else
      if attempts > 0 do
        Process.sleep(10)
        wait_for_flags(path, names, attempts - 1)
      else
        flunk("persistence file missing flags #{inspect(names)}: #{inspect_file(path)}")
      end
    end
  end

  # Polls until the JSON file no longer contains the given flag name.
  defp wait_for_absence(path, name, attempts \\ 100) do
    name_str = Atom.to_string(name)

    if file_has_names?(path, [name_str]) do
      if attempts > 0 do
        Process.sleep(10)
        wait_for_absence(path, name, attempts - 1)
      else
        flunk("persistence file still contains flag #{name}: #{inspect_file(path)}")
      end
    else
      :ok
    end
  end

  defp file_has_names?(path, names) do
    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, %{} = json} -> Enum.all?(names, &Map.has_key?(json, &1))
          _ -> false
        end

      {:error, _} ->
        false
    end
  end

  defp inspect_file(path) do
    case File.read(path) do
      {:ok, contents} -> contents
      {:error, reason} -> "unreadable (#{inspect(reason)})"
    end
  end

  defp stop_store do
    # The Store is registered under its module name by start_link/1.
    GenServer.stop(Store, :normal, 5_000)
  end

  defp start_store do
    Store.start_link([])
  end

  # Full application restart: stops the Supervisor (and the Store) and
  # boots it again with fresh state, so persisted flags are reloaded.
  defp restart_app do
    :ok = Application.stop(:botica)
    {:ok, _apps} = Application.ensure_all_started(:botica)
  end
end
