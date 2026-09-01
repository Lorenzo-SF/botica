defmodule Botica.Runner.CheckRunnerTest do
  use ExUnit.Case, async: false

  alias Botica.Check.Result
  alias Botica.Runner.CheckRunner

  defp slow_check(ms) do
    %{
      id: :slow,
      name: "Slow check",
      check: fn ->
        Process.sleep(ms)
        {:ok, "done"}
      end
    }
  end

  defp fast_check, do: %{id: :fast, name: "Fast check", check: fn -> {:ok, "fast"} end}

  defp crash_check do
    %{
      id: :crash,
      name: "Crash check",
      check: fn ->
        raise "boom"
      end
    }
  end

  test "returns ok result for a fast check" do
    assert {:ok, %{status: :ok, message: "fast"}} = CheckRunner.run_check(fast_check(), 1_000)
  end

  test "times out a hung check and returns timeout result" do
    assert {:ok, %{status: :error, message: "timeout: check exceeded 100ms"}} =
             CheckRunner.run_check(slow_check(2_000), 100)
  end

  test "default timeout is 5 seconds" do
    assert {:ok, %{status: :ok}} = CheckRunner.run_check(fast_check())
  end

  test "a crash inside the check becomes an exception result, not a crash" do
    assert {:ok, %{status: :error, message: "exception: boom"}} =
             CheckRunner.run_check(crash_check(), 1_000)
  end

  test "a hung check does not block a subsequent check" do
    # Run the slow check with a short timeout in one process; a separate
    # fast check must complete while the slow one is still sleeping.
    parent = self()

    spawn(fn ->
      {:ok, result} = CheckRunner.run_check(slow_check(1_000), 50)
      send(parent, {:slow, result.status})
    end)

    Process.sleep(10)
    assert {:ok, %{status: :ok}} = CheckRunner.run_check(fast_check(), 1_000)

    assert_receive {:slow, status}, 2_000
    assert status == :error
  end
end