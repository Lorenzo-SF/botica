defmodule Botica.Doctor.Reporter do
  @moduledoc """
  Result aggregation and reporting for `Botica.Doctor`.

  Splits out the reporting helpers from `Botica.Doctor` so the doctor
  remains focused on orchestration.

  Not part of the public API — used only by `Botica.Doctor`.
  """

  @doc """
  Aggregates check results into a summary map.

  Returns `%{ok: n, warning: n, error: n, total: n, passed?: boolean}`.
  """
  @spec summary([map()]) :: %{
          ok: non_neg_integer(),
          warning: non_neg_integer(),
          error: non_neg_integer(),
          total: non_neg_integer(),
          passed?: boolean()
        }
  def summary(results) do
    Botica.Check.Result.summarize(results)
  end

  @doc """
  Derives an overall health status from a summary.

  Returns `:ok` if all pass, `:degraded` if some warnings, `:fail` if any error.
  """
  @spec derive_status(map()) :: :ok | :degraded | :fail
  def derive_status(%{error: n}) when n > 0, do: :fail
  def derive_status(%{warning: n}) when n > 0, do: :degraded
  def derive_status(_), do: :ok
end
