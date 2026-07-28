defmodule Botica.RuntimeBugsTest do
  @moduledoc """
  Regression tests for the five runtime bugs that the audit identified
  against `Botica.Runner.Executor`, `Botica.Validation`, and
  `Botica.Flags.Store`.

  These tests use a separate process (Task) to isolate the caller from
  the executor — if the caller dies from a leaked exit signal, the
  Task fails.
  """
  use ExUnit.Case, async: true

  alias Botica.Doctor
  alias Botica.Flags
  alias Botica.Flags.Store
  alias Botica.Runner.Executor
  alias Botica.Validation

  defp make_check(id, check_fn, opts \\ []) do
    %{
      id: id,
      name: Atom.to_string(id),
      description: "",
      priority: 1,
      tags: [],
      timeout: Keyword.get(opts, :timeout),
      check: check_fn,
      fix: nil,
      fix_command: nil
    }
  end

  # Returns a list of fresh atoms for use as check ids in async tests.
  # The atoms are pre-allocated at module compile time via the
  # @check_id_pool attribute so we avoid String.to_atom at runtime.
  @check_id_pool Enum.map(1..64, &:"rt_check_#{&1}")

  defp unique_check_ids(count) do
    Enum.take(@check_id_pool, count)
  end

  defp config_with(checks) do
    %{app_name: "test", checks: checks}
  end

  describe "Bug 1: crash isolation (no link from spawn_opt)" do
    test "check calling exit(:boom) does NOT kill the caller" do
      caller =
        Task.async(fn ->
          config =
            config_with([
              make_check(:explode, fn -> exit(:boom) end)
            ])

          Doctor.run(config, timeout: 2_000)
        end)

      # If bug 1 were real, the Task would receive an :exit signal and
      # the Task.await would raise. We expect a clean {:ok, _} result.
      assert {:ok, [result]} = Task.await(caller, 3_000)
      assert result.status == :error
      assert result.message =~ "exception"
    end

    test "check calling exit(:shutdown) is also contained" do
      caller =
        Task.async(fn ->
          config =
            config_with([
              make_check(:shutdown, fn -> exit(:shutdown) end)
            ])

          Doctor.run(config, timeout: 2_000)
        end)

      assert {:ok, [result]} = Task.await(caller, 3_000)
      assert result.status == :error
    end

    test "check calling throw(:something) is contained (rescued)" do
      caller =
        Task.async(fn ->
          config =
            config_with([
              make_check(:throw_check, fn -> throw(:nope) end)
            ])

          Doctor.run(config, timeout: 2_000)
        end)

      assert {:ok, [result]} = Task.await(caller, 3_000)
      assert result.status == :error
    end
  end

  describe "Bug 2: empty checks list" do
    test "validate_config rejects empty checks" do
      assert {:error, "config.checks must contain at least one check"} =
               Validation.validate_config(%{app_name: "t", checks: []})
    end

    test "Doctor.run returns {:error, ...} for empty checks (no ArgumentError)" do
      # Before the fix: max_concurrency = 0 → Task.async_stream raises
      # ArgumentError. After the fix: validation rejects early.
      result = Doctor.run(%{app_name: "t", checks: []}, timeout: 1_000)
      assert {:error, "config.checks must contain at least one check"} = result
    end

    test "Executor.execute also rejects empty checks" do
      config = %{app_name: "t", checks: []}

      assert {:error, "config.checks must contain at least one check"} =
               Executor.execute(config)
    end
  end

  describe "Bug 3: :DOWN message leak" do
    test "successful checks do not leave :DOWN messages in caller mailbox" do
      test_pid = self()

      # The Task.async_stream workers isolate from the caller's mailbox
      # in the default parallel path, so this only applies to the
      # sequential path (continue_on_error: false / stop_on_first_error).
      caller =
        spawn(fn ->
          config =
            config_with(
              unique_check_ids(3)
              |> Enum.map(fn id -> make_check(id, fn -> {:ok, "ok"} end) end)
            )

          Doctor.run(config, continue_on_error: false, stop_on_first_error: true)
          Process.sleep(200)
          msgs = Process.info(self(), :messages) |> elem(1)
          send(test_pid, {:msgs, msgs})
        end)

      assert_receive {:msgs, msgs}, 3_000

      down_msgs = Enum.filter(msgs, fn m -> match?({:DOWN, _, _, _, _}, m) end)

      assert down_msgs == [],
             "Expected no :DOWN leaks in caller mailbox, got: #{inspect(down_msgs)}"
    end

    test "checks that raise and get rescued do not leak :DOWN either" do
      test_pid = self()

      spawn(fn ->
        config =
          config_with(
            unique_check_ids(2)
            |> Enum.map(fn id -> make_check(id, fn -> raise "boom" end) end)
          )

        Doctor.run(config, continue_on_error: false)
        Process.sleep(200)
        msgs = Process.info(self(), :messages) |> elem(1)
        send(test_pid, {:msgs, msgs})
      end)

      assert_receive {:msgs, msgs}, 3_000

      down_msgs = Enum.filter(msgs, fn m -> match?({:DOWN, _, _, _, _}, m) end)
      assert down_msgs == []
    end
  end

  describe "Bug 4: stale check_result messages" do
    test "late result from timed-out check is NOT consumed by next check" do
      # First check: sleeps then sends its result, but the parent's
      # timeout fires first. The child's send lands in the parent's
      # mailbox AFTER the timeout. With the old untagged message
      # scheme, the NEXT check's receive would match this stale
      # message and return the wrong result.
      test_pid = self()

      spawn(fn ->
        config = %{
          app_name: "stale",
          checks: [
            make_check(
              :stale,
              fn ->
                # Slower than the 30ms timeout below but the child
                # still tries to send its result before being killed.
                Process.sleep(50)
                {:ok, "stale-check-1-result"}
              end,
              timeout: 30
            ),
            make_check(
              :correct,
              fn ->
                Process.sleep(10)
                {:ok, "stale-check-2-result"}
              end,
              timeout: 1_000
            )
          ]
        }

        # Sequential path: each call to execute_single_check runs
        # in the caller's process, so leftover messages can leak.
        {:ok, results} =
          Doctor.run(config, continue_on_error: false, stop_on_first_error: false)

        send(test_pid, {:results, results})
      end)

      assert_receive {:results, results}, 5_000

      # The first check times out (status: :error, timeout message).
      # The second check should produce its own result, NOT the stale
      # first-check result.
      stale_result = Enum.find(results, &(&1.id == :stale))
      correct_result = Enum.find(results, &(&1.id == :correct))

      assert stale_result.status == :error
      assert stale_result.message =~ "timeout"

      # Critical assertion: the second check's result must be ITS OWN,
      # not the leftover first-check's result.
      assert correct_result.message == "stale-check-2-result",
             "Second check consumed stale message from first check: #{inspect(correct_result)}"
    end
  end

  describe "Bug 5: orphaned :stats handler" do
    test "Botica.Flags.Store.stats/0 is exposed as public API" do
      assert function_exported?(Store, :stats, 0)
    end

    test "stats/0 returns writes and count" do
      Store.table() |> :ets.delete_all_objects()
      Flags.define(:stats_test_flag, default: true)
      assert %{writes: writes, count: count} = Store.stats()
      assert writes >= 1
      assert count >= 1
    end
  end
end
