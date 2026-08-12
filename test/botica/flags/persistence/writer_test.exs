defmodule Botica.Flags.Persistence.WriterTest do
  @moduledoc """
  Tests for `Botica.Flags.Persistence.Writer`.
  """

  use ExUnit.Case, async: false

  alias Botica.Flags.Flag
  alias Botica.Flags.Persistence
  alias Botica.Flags.Persistence.Writer

  # Adapter that always fails — verifies the writer logs and continues.
  defmodule FailingAdapter do
    @behaviour Persistence

    @impl true
    def load_all, do: {:error, :nope}
    @impl true
    def save_flag(_flag), do: {:error, :disk_full}
    @impl true
    def delete_flag(_name), do: {:error, :disk_full}
  end

  # Adapter that records calls into a shared Agent.
  defmodule RecordingAdapter do
    @behaviour Persistence

    @impl true
    def load_all, do: {:ok, []}

    @impl true
    def save_flag(flag) do
      Agent.update(:writer_test_events, &[{:saved, flag.name} | &1])
      :ok
    end

    @impl true
    def delete_flag(name) do
      Agent.update(:writer_test_events, &[{:deleted, name} | &1])
      :ok
    end
  end

  setup do
    {:ok, _} = Agent.start_link(fn -> [] end, name: :writer_test_events)
    :ok
  end

  test "save/1 writes through to the configured adapter" do
    Application.put_env(:botica, :flags_persistence, adapter: RecordingAdapter, opts: [])
    on_exit(fn -> Application.put_env(:botica, :flags_persistence, []) end)

    :ok = Writer.save(Flag.new(:writer_save, default: true))

    wait_for(fn -> Agent.get(:writer_test_events, & &1) != [] end)
    assert {:saved, :writer_save} in Agent.get(:writer_test_events, & &1)
  end

  test "delete/1 writes through to the configured adapter" do
    Application.put_env(:botica, :flags_persistence, adapter: RecordingAdapter, opts: [])
    on_exit(fn -> Application.put_env(:botica, :flags_persistence, []) end)

    :ok = Writer.delete(:writer_delete)

    wait_for(fn -> Agent.get(:writer_test_events, & &1) != [] end)
    assert {:deleted, :writer_delete} in Agent.get(:writer_test_events, & &1)
  end

  test "adapter failures are logged and do not crash the writer" do
    Application.put_env(:botica, :flags_persistence, adapter: FailingAdapter, opts: [])
    on_exit(fn -> Application.put_env(:botica, :flags_persistence, []) end)

    :ok = Writer.save(Flag.new(:writer_fail, default: true))
    # Writer must still be alive and responsive.
    assert Writer.pending() >= 1

    :ok = Writer.delete(:writer_fail)
    assert Writer.pending() >= 2
  end

  defp wait_for(fun, attempts \\ 50) do
    if fun.() do
      :ok
    else
      if attempts > 0 do
        Process.sleep(10)
        wait_for(fun, attempts - 1)
      else
        flunk("condition not met in time")
      end
    end
  end
end
