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

  ## Options

  - `:timeout` - Global timeout in milliseconds for each check (default: 30_000)
  - `:stop_on_first_error` - Stop executing remaining checks after first error
  - `:continue_on_error` - Continue executing checks even if some fail (default: true)

  ## Per-check timeouts

  Individual checks can specify their own timeout in their definition:

      %{
        id: :slow_check,
        timeout: 5000,  # This check gets 5 seconds instead of global 30s
        check: fn -> ... end
      }

  ## Timeout behavior

  When a check times out, it returns an error result with a descriptive message.
  The timeout is applied per-check, not for the entire run.
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
            {:ok, result} = execute_single_check(check, @default_timeout)
            result
          end)

        {:ok, results}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp validate_config(config) do
    cond do
      not is_map(config) ->
        {:error, "config must be a map"}

      not is_binary(Map.get(config, :app_name, "")) ->
        {:error, "config.app_name must be a string"}

      not is_list(Map.get(config, :checks, nil)) ->
        {:error, "config.checks must be a list"}

      true ->
        :ok
    end
  end

  defp run_checks(checks, opts, run_opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    continue_on_error = Keyword.get(run_opts, :continue_on_error, true)
    stop_on_first_error = Keyword.get(run_opts, :stop_on_first_error, false)

    # Build check functions with timeout support
    funs =
      Enum.map(checks, fn check ->
        check_timeout = Map.get(check, :timeout, timeout)
        fn -> execute_single_check(check, check_timeout) end
      end)

    # stop_on_first_error takes precedence: halt at the first error
    # regardless of continue_on_error. Otherwise, if continue_on_error
    # is false, stop on the first error. Otherwise, run in parallel.
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
            timeout: timeout + 1_000,
            ordered: true
          )
          |> Enum.map(fn
            {:ok, result} -> result
            {:exit, reason} -> {:error, %{error: reason}}
          end)

        results = process_results(checks, raw_results)
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

  defp execute_single_check(check, timeout) do
    effective_timeout = timeout || @default_timeout

    task =
      Task.async(fn ->
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
      end)

    result = Task.await(task, effective_timeout)

    case result do
      {:ok, _} = ok -> ok
      {:error, reason} -> {:error, %{error: reason}}
    end
  catch
    :exit, _reason ->
      {:ok, Result.from_timeout(check, timeout || @default_timeout)}
  end

  defp process_results(checks, raw_results) do
    checks
    |> Enum.with_index()
    |> Enum.map(fn {check, idx} ->
      case Enum.at(raw_results, idx) do
        {:ok, result} when is_map(result) ->
          result

        {:error, %{error: :timeout}} ->
          Result.from_timeout(check, @default_timeout)

        {:error, %{error: exc}} ->
          Result.from_exception(check, exc)

        other ->
          Result.build(check, :error, "unexpected: #{inspect(other)}")
      end
    end)
  end
end
