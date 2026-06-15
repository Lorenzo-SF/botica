defmodule Botica.Runner.ExecutorTest do
  use ExUnit.Case, async: true

  alias Botica.Runner.Executor

  defp make_check(id, result_fn, opts \\ []) do
    %{
      id: id,
      name: Atom.to_string(id),
      description: "",
      priority: 1,
      tags: [],
      timeout: Keyword.get(opts, :timeout),
      check: result_fn,
      fix: nil,
      fix_command: nil
    }
  end

  defp config_with(checks) do
    %{app_name: "test", checks: checks}
  end

  describe "stop_on_first_error" do
    test "default (false) runs all checks even on errors" do
      checks = [
        make_check(:a, fn -> {:ok, "ok"} end),
        make_check(:b, fn -> {:error, "boom"} end),
        make_check(:c, fn -> {:ok, "ok"} end)
      ]

      {:ok, results} = Executor.execute(config_with(checks), [])
      assert length(results) == 3
    end

    test "with stop_on_first_error true stops after first error when continue_on_error is false" do
      checks = [
        make_check(:a, fn -> {:ok, "ok"} end),
        make_check(:b, fn -> {:error, "boom"} end),
        make_check(:c, fn -> {:ok, "ok"} end)
      ]

      {:ok, results} =
        Executor.execute(config_with(checks), stop_on_first_error: true, continue_on_error: false)

      # Should run a, b, but stop before c
      assert length(results) == 2
      ids = Enum.map(results, & &1.id)
      assert :a in ids
      assert :b in ids
      refute :c in ids
    end

    test "with stop_on_first_error true AND continue_on_error true stops after first error" do
      checks = [
        make_check(:a, fn -> {:error, "first"} end),
        make_check(:b, fn -> {:error, "second"} end)
      ]

      {:ok, results} =
        Executor.execute(config_with(checks), stop_on_first_error: true, continue_on_error: true)

      # With stop_on_first_error, only first error is reported
      assert length(results) == 1
      assert hd(results).id == :a
    end

    test "stop_on_first_error with all ok checks runs all" do
      checks = [
        make_check(:a, fn -> {:ok, "ok"} end),
        make_check(:b, fn -> {:ok, "ok"} end)
      ]

      {:ok, results} =
        Executor.execute(config_with(checks), stop_on_first_error: true, continue_on_error: false)

      assert length(results) == 2
    end
  end

  describe "continue_on_error" do
    test "default (true) continues on errors" do
      checks = [
        make_check(:a, fn -> {:error, "boom"} end),
        make_check(:b, fn -> {:ok, "ok"} end)
      ]

      {:ok, results} = Executor.execute(config_with(checks), [])
      assert length(results) == 2
    end

    test "false stops on first error" do
      checks = [
        make_check(:a, fn -> {:error, "boom"} end),
        make_check(:b, fn -> {:ok, "ok"} end)
      ]

      {:ok, results} = Executor.execute(config_with(checks), continue_on_error: false)

      assert length(results) == 1
      assert hd(results).id == :a
    end
  end

  describe "execution order" do
    test "respects priority (lower first)" do
      checks = [
        make_check(:c, fn -> {:ok, "c"} end) |> Map.put(:priority, 3),
        make_check(:a, fn -> {:ok, "a"} end) |> Map.put(:priority, 1),
        make_check(:b, fn -> {:ok, "b"} end) |> Map.put(:priority, 2)
      ]

      {:ok, results} = Executor.execute(config_with(checks), [])

      ids = Enum.map(results, & &1.id)
      assert ids == [:a, :b, :c]
    end
  end
end
