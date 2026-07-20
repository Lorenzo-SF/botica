defmodule Botica.Runner.Executor do
  @moduledoc """
  Executes health checks in parallel with timeout support.

  This module provides the core execution engine for Botica checks,
  running them in parallel while respecting timeout constraints.
  """

  alias Botica.Check.Result
  alias Botica.Runner.Sequencer
  alias Botica.Types

  @default_timeout 30_000

  # Cap Task.async_stream concurrency. Without this, a 1000-check
  # config launches 1000 processes simultaneously and can exhaust
  # schedulers / file descriptors / database connections.
  @max_default_concurrency 8

  @doc """
  Executes all checks in parallel and returns structured results.
  """
  @spec execute(Types.config()) :: {:ok, [Types.result()]} | {:error, String.t()}
  def execute(config) do
    execute(config, [])
  end

  @spec execute(Types.config(), Types.executor_options()) ::
          {:ok, [Types.result()]} | {:error, String.t()}
  def execute(config, opts) when is_list(opts) do
    case validate_config(config) do
      :ok ->
        sorted = Sequencer.sort(config.checks)
        continue_on_error = Keyword.get(opts, :continue_on_error, true)
        stop_on_first_error = Keyword.get(opts, :stop_on_first_error, false)

        run_checks(sorted, opts,
          continue_on_error: continue_on_error,
          stop_on_first_error: stop_on_first_error
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Executes checks sequentially (for debugging or ordered execution).
  """
  @spec execute_sequential(Types.config()) :: {:ok, [Types.result()]} | {:error, String.t()}
  def execute_sequential(config) do
    case validate_config(config) do
      :ok ->
        sorted = Sequencer.sort(config.checks)

        results =
          Enum.map(sorted, fn check ->
            {:ok, result} = execute_single_check(check, Map.get(check, :timeout, @default_timeout))
            result
          end)

        {:ok, results}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defdelegate validate_config(config), to: Botica.Validation

  defp run_checks(checks, opts, run_opts) do
    effective_timeout = Keyword.get(opts, :timeout, @default_timeout)
    continue_on_error = Keyword.get(run_opts, :continue_on_error, true)
    stop_on_first_error = Keyword.get(run_opts, :stop_on_first_error, false)

    funs =
      Enum.map(checks, fn check ->
        check_timeout = Map.get(check, :timeout, effective_timeout)
        fn -> execute_single_check(check, check_timeout) end
      end)

    cond do
      stop_on_first_error ->
        run_sequential_with_short_circuit(checks, funs, true, true)

      not continue_on_error ->
        run_sequential_with_short_circuit(checks, funs, false, false)

      true ->
        max_concurrency = min(length(funs), @max_default_concurrency)

        raw_results =
          funs
          |> Task.async_stream(fn fun -> fun.() end,
            max_concurrency: max_concurrency,
            timeout: effective_timeout + 1_000,
            ordered: true
          )
          |> Enum.map(fn
            {:ok, result} -> result
            {:exit, reason} -> {:error, %{error: reason}}
          end)

        results = process_results(checks, raw_results, effective_timeout)
        {:ok, results}
    end
  end

  defp run_sequential_with_short_circuit(checks, funs, continue_on_error, stop_on_first_error) do
    initial_acc = {:ok, []}

    reduced =
      checks
      |> Enum.zip(funs)
      |> Enum.reduce_while(initial_acc, fn {_check, fun}, {:ok, acc} ->
        run_one_check(fun, acc, continue_on_error, stop_on_first_error)
      end)

    case reduced do
      {:ok, results} -> {:ok, results}
      err -> err
    end
  end

  defp run_one_check(fun, acc, continue_on_error, stop_on_first_error) do
    case fun.() do
      {:ok, %{status: :error} = result} ->
        if continue_on_error and not stop_on_first_error do
          {:cont, {:ok, [result | acc]}}
        else
          {:halt, {:ok, Enum.reverse([result | acc])}}
        end

      {:ok, result} ->
        {:cont, {:ok, [result | acc]}}

      {:error, _} = err ->
        {:halt, err}
    end
  end

  # Runs a single check in an unlinked process so crashes do not
  # propagate to the caller. Uses :proc_lib.spawn_opt/2 with link: false.
  defp execute_single_check(check, timeout) do
    effective_timeout = timeout || @default_timeout
    parent = self()

    # :proc_lib.spawn_opt with :monitor returns {pid, monitor_ref}
    {pid, monitor_ref} =
      :proc_lib.spawn_opt(fn ->
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

        send(parent, {:check_result, result})
      end, [:link, :monitor])

    result =
      receive do
        {:check_result, _} = msg ->
          msg

        {:DOWN, ^monitor_ref, :process, ^pid, :normal} ->
          {:exit, :timeout}

        {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
          {:exit, reason}
      after
        effective_timeout ->
          Process.exit(pid, :kill)
          {:exit, :timeout}
      end

    case result do
      {:check_result, {:ok, _} = ok} ->
        ok

      {:exit, :timeout} ->
        {:ok, Result.from_timeout(check, effective_timeout)}

      {:exit, _reason} ->
        {:error, %{error: :task_crashed}}
    end
  end

  # Converts any term to an Exception struct for Result.from_exception.
  defp to_exception(term) do
    if is_struct(term, Exception), do: term, else: RuntimeError.exception(inspect(term))
  end

  defp process_results(checks, raw_results, effective_timeout) do
    checks
    |> Enum.zip(raw_results)
    |> Enum.map(fn {check, raw} -> resolve_result(check, raw, effective_timeout) end)
  end

  defp resolve_result(_check, {:ok, result}, _timeout) when is_map(result), do: result
  defp resolve_result(check, {:error, %{error: :timeout}}, timeout), do: Result.from_timeout(check, timeout)

  defp resolve_result(check, {:error, %{error: exc}}, _timeout) do
    Result.from_exception(check, to_exception(exc))
  end

  defp resolve_result(check, other, _timeout) do
    Result.build(check, :error, "unexpected: #{inspect(other)}")
  end
end
