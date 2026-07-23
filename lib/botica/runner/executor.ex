defmodule Botica.Runner.Executor do
  @moduledoc """
  Executes health checks in parallel with timeout support.

  This module provides the core execution engine for Botica checks,
  running them in parallel while respecting timeout constraints. Low-level
  check execution is delegated to `Botica.Runner.CheckRunner`.
  """

  alias Botica.Check.Result
  alias Botica.Runner.CheckRunner
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

  @doc """
  Executes all checks in parallel with custom options. See module
  `@moduledoc` for the option list.
  """
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
            {:ok, result} =
              CheckRunner.run_check(check, Map.get(check, :timeout, @default_timeout))

            result
          end)

        {:ok, results}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  @doc false
  defdelegate validate_config(config), to: Botica.Validation

  defp run_checks(checks, opts, run_opts) do
    effective_timeout = Keyword.get(opts, :timeout, @default_timeout)
    continue_on_error = Keyword.get(run_opts, :continue_on_error, true)
    stop_on_first_error = Keyword.get(run_opts, :stop_on_first_error, false)

    funs =
      Enum.map(checks, fn check ->
        check_timeout = Map.get(check, :timeout, effective_timeout)
        fn -> CheckRunner.run_check(check, check_timeout) end
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

  defp process_results(checks, raw_results, effective_timeout) do
    checks
    |> Enum.zip(raw_results)
    |> Enum.map(fn {check, raw} -> CheckRunner.resolve_result(check, raw, effective_timeout) end)
  end
end
