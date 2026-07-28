defmodule Botica.Runner.CheckRunner do
  @moduledoc """
  Runs a single health check in an isolated process with timeout and monitoring.

  This module handles the low-level execution of a check function inside a
  monitored child process. It is used by `Botica.Runner.Executor` for both
  parallel and sequential execution modes.
  """

  alias Botica.Check.Result
  alias Botica.Types

  @default_timeout 30_000

  @doc """
  Runs a single check in an unlinked, monitored process with timeout.

  Two safety mechanisms at play:

  1. `:link` is NOT in the spawn_opt list. An `exit/1` inside the check
     propagates only to the child, not to the caller.
  2. The result message is tagged with a unique `tag_ref` (`make_ref/0`)
     so that stale messages from a previous (timed-out) check cannot be
     matched by the next `receive`.
  """
  @spec run_check(Types.check_def(), timeout :: non_neg_integer()) ::
          {:ok, Types.result()} | {:error, :timeout} | {:error, :task_crashed}
  def run_check(check, timeout \\ @default_timeout) do
    effective_timeout = timeout || @default_timeout
    parent = self()
    tag_ref = make_ref()

    {check_pid, monitor_ref} =
      :proc_lib.spawn_opt(
        fn ->
          result =
            try do
              case check.check.() do
                {:ok, msg} -> {:ok, Result.build(check, :ok, msg)}
                {:warning, msg} -> {:ok, Result.build(check, :warning, msg)}
                {:error, msg} -> {:ok, Result.build(check, :error, msg)}
              end
            rescue
              error ->
                {:ok, Result.from_exception(check, error)}
            end

          send(parent, {tag_ref, :check_result, result})
        end,
        [:monitor]
      )

    result =
      receive do
        {^tag_ref, :check_result, _} = msg ->
          msg

        {:DOWN, ^monitor_ref, :process, ^check_pid, :normal} ->
          {:exit, :timeout}

        {:DOWN, ^monitor_ref, :process, ^check_pid, reason} ->
          {:exit, reason}
      after
        effective_timeout ->
          Process.exit(check_pid, :kill)
          {:exit, :timeout}
      end

    # Always demonitor and flush any pending :DOWN message so it does not
    # leak into the caller's mailbox. Also drain any tagged check_result
    # message that arrived after the timeout/kill (race window).
    Process.demonitor(monitor_ref, [:flush])

    receive do
      {^tag_ref, :check_result, _} -> :ok
    after
      0 -> :ok
    end

    case result do
      {^tag_ref, :check_result, {:ok, _} = ok} ->
        ok

      {:exit, :timeout} ->
        {:ok, Result.from_timeout(check, effective_timeout)}

      {:exit, _reason} ->
        {:error, %{error: :task_crashed}}
    end
  end

  @doc """
  Converts any term to an Exception struct for `Result.from_exception`.
  """
  @spec to_exception(term()) :: Exception.t()
  def to_exception(term) do
    if is_struct(term, Exception), do: term, else: RuntimeError.exception(inspect(term))
  end

  @doc """
  Resolves a raw check result into a structured result map.
  """
  @spec resolve_result(Types.check_def(), term(), non_neg_integer()) :: Types.result()
  def resolve_result(_check, {:ok, result}, _timeout) when is_map(result), do: result

  def resolve_result(check, {:error, %{error: :timeout}}, timeout),
    do: Result.from_timeout(check, timeout)

  def resolve_result(check, {:error, %{error: exc}}, _timeout) do
    Result.from_exception(check, to_exception(exc))
  end

  def resolve_result(check, other, _timeout) do
    Result.build(check, :error, "unexpected: #{inspect(other)}")
  end
end
