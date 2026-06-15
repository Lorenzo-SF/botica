# credo:disable-for-this-file
defmodule Botica.Repair.Fixer do
  @moduledoc """
  Auto-repair logic for health checks that failed.

  This module handles running fix functions for checks that returned
  an error status, providing detailed reporting of what was applied,
  failed, or skipped.
  """

  alias Botica.Types

  @doc """
  Runs fixes for all checks that have an error status.

  Returns a detailed report of what was applied, failed, or skipped.

  ## Examples

      iex> config = %{
      ...>   app_name: \"test\",
      ...>   checks: [
      ...>     %{
      ...>       id: :fail1,
      ...>       name: \"Fail 1\",
      ...>       check: fn -> {:error, \"problem\"} end,
      ...>       fix: fn -> {:ok, \"fixed!\"} end
      ...>     },
      ...>     %{
      ...>       id: :fail2,
      ...>       name: \"Fail 2\",
      ...>       check: fn -> {:error, \"another problem\"} end,
      ...>       fix: fn -> {:error, \"can't fix\"} end
      ...>     },
      ...>     %{
      ...>       id: :ok,
      ...>       name: \"OK\",
      ...>       check: fn -> {:ok, \"good\"} end,
      ...>       fix: fn -> :skipped end
      ...>     }
      ...>   ]
      ...> }
      iex> {:ok, results} = Botica.Doctor.run(config)
      iex> report = Botica.Repair.Fixer.fix(config, results)
      iex> report.applied
      [:fail1]
      iex> report.failed
      [{:fail2, \"can't fix\"}]
      iex> report.skipped
      [:ok]
  """
  @spec fix(Types.config(), [Types.result()]) :: {:ok, Types.fix_report()} | {:error, String.t()}
  def fix(config, results) when is_list(results) do
    config_map = Map.new(config.checks, fn c -> {c.id, c} end)

    {applied, failed, skipped} =
      Enum.reduce(results, {[], [], []}, fn result, {applied, failed, skipped} ->
        case Map.get(config_map, result.id) do
          nil ->
            {applied, failed, skipped}

          %{fix: nil} ->
            # Check has no fix function - skip it
            {applied, failed, [result.id | skipped]}

          %{fix: fix_fn} when is_function(fix_fn, 0) ->
            maybe_apply_fix(result, fix_fn, applied, failed, skipped)
        end
      end)

    report = %{
      applied: Enum.reverse(applied),
      failed: Enum.reverse(failed),
      skipped: Enum.reverse(skipped)
    }

    {:ok, report}
  end

  @doc """
  Runs fixes for a single check by ID.

  ## Examples

      iex> config = %{
      ...>   app_name: \"test\",
      ...>   checks: [
      ...>     %{
      ...>       id: :my_check,
      ...>       name: \"My Check\",
      ...>       check: fn -> {:error, \"problem\"} end,
      ...>       fix: fn -> {:ok, \"fixed!\"} end
      ...>     }
      ...>   ]
      ...> }
      iex> Botica.Repair.Fixer.fix_one(config, :my_check)
      {:ok, :applied}
  """
  @spec fix_one(Types.config(), Types.check_id()) ::
          {:ok, :applied | :failed | :skipped} | {:error, String.t()}
  def fix_one(config, check_id) do
    case Enum.find(config.checks, &(&1.id == check_id)) do
      nil ->
        {:error, "check not found: #{inspect(check_id)}"}

      %{fix: nil} ->
        {:ok, :skipped}

      %{fix: fix_fn} when is_function(fix_fn, 0) ->
        case apply_fix(fix_fn) do
          {:ok, _msg} -> {:ok, :applied}
          {:error, _msg} -> {:ok, :failed}
          :skipped -> {:ok, :skipped}
        end
    end
  end

  @doc """
  Validates that a fix function has the correct arity.

  ## Examples

      iex> Botica.Repair.Fixer.valid_fix?(fn -> :ok end)
      true
      iex> Botica.Repair.Fixer.valid_fix?(fn _ -> :ok end)
      false
      iex> Botica.Repair.Fixer.valid_fix?(nil)
      false
  """
  @spec valid_fix?((... -> any()) | nil | any()) :: boolean()
  def valid_fix?(fix) when is_function(fix, 0), do: true
  def valid_fix?(nil), do: false
  def valid_fix?(_), do: false

  # Private functions

  defp maybe_apply_fix(result, fix_fn, applied, failed, skipped) do
    if result.status == :error do
      # Only attempt fix for checks that errored
      case apply_fix(fix_fn) do
        {:ok, _msg} ->
          {[result.id | applied], failed, skipped}

        :ok ->
          # Some fix functions (like Agent.update) return :ok
          {[result.id | applied], failed, skipped}

        {:error, msg} ->
          {applied, [{result.id, msg} | failed], skipped}

        :skipped ->
          {applied, failed, [result.id | skipped]}
      end
    else
      # Check passed or warned - skip
      {applied, failed, [result.id | skipped]}
    end
  end

  defp apply_fix(fix_fn) do
    try do
      fix_fn.()
    rescue
      error ->
        {:error, Exception.message(error)}
    catch
      kind, reason ->
        {:error, Exception.format(kind, reason, __STACKTRACE__)}
    end
  end
end
