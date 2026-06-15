defmodule Botica.Check.Result do
  @moduledoc """
  Logic for building and processing check results.
  """

  alias Botica.Types

  @doc """
  Builds a result map from a check definition and a check result tuple.

  ## Examples

      iex> check = %{id: :test, name: \"Test\", fix_command: \"fix it\"}
      iex> Botica.Check.Result.build(check, :ok, \"everything fine\")
      %{id: :test, name: \"Test\", status: :ok, message: \"everything fine\", fix_command: \"fix it\"}
  """
  @spec build(Types.check_def(), Types.status(), String.t()) :: Types.result()
  def build(check, status, message) do
    %{
      id: check.id,
      name: check.name,
      status: status,
      message: message,
      fix_command: Map.get(check, :fix_command)
    }
  end

  @doc """
  Converts a raw check result tuple to a status and message.

  ## Examples

      iex> Botica.Check.Result.to_status({:ok, \"good\"})
      {:ok, \"good\"}

      iex> Botica.Check.Result.to_status({:warning, \"low memory\"})
      {:warning, \"low memory\"}

      iex> Botica.Check.Result.to_status({:error, \"connection failed\"})
      {:error, \"connection failed\"}
  """
  @spec to_status(Types.check_result()) :: {Types.status(), String.t()}
  def to_status({:ok, msg}), do: {:ok, msg}
  def to_status({:warning, msg}), do: {:warning, msg}
  def to_status({:error, msg}), do: {:error, msg}

  @doc """
  Builds a result from an exception.

  ## Examples

      iex> check = %{id: :boom, name: \"Boom\", fix_command: nil}
      iex> result = Botica.Check.Result.from_exception(check, %RuntimeError{message: \"oops\"})
      iex> result.status
      :error
      iex> result.message
      \"exception: oops\"
  """
  @spec from_exception(Types.check_def(), Exception.t()) :: Types.result()
  def from_exception(check, exception) do
    build(check, :error, "exception: #{Exception.message(exception)}")
  end

  @doc """
  Builds a result for a timeout situation.

  ## Examples

      iex> check = %{id: :slow, name: \"Slow\", fix_command: nil}
      iex> result = Botica.Check.Result.from_timeout(check, 5000)
      iex> result.status
      :error
      iex> result.message
      \"timeout: check exceeded 5000ms\"
  """
  @spec from_timeout(Types.check_def(), non_neg_integer()) :: Types.result()
  def from_timeout(check, timeout_ms) do
    build(check, :error, "timeout: check exceeded #{timeout_ms}ms")
  end

  @doc """
  Calculates a summary from a list of results.

  ## Examples

      iex> results = [
      ...>   %{status: :ok},
      ...>   %{status: :ok},
      ...>   %{status: :warning},
      ...>   %{status: :error}
      ...> ]
      iex> Botica.Check.Result.summarize(results)
      %{ok: 2, warning: 1, error: 1, total: 4, passed?: false}
  """
  @spec summarize([Types.result()]) :: Types.summary()
  def summarize(results) do
    ok_count = Enum.count(results, &(&1.status == :ok))
    warning_count = Enum.count(results, &(&1.status == :warning))
    error_count = Enum.count(results, &(&1.status == :error))

    %{
      ok: ok_count,
      warning: warning_count,
      error: error_count,
      total: length(results),
      passed?: error_count == 0
    }
  end

  @doc """
  Determines the overall health status from a summary.

  ## Examples

      iex> Botica.Check.Result.health_status(%{error: 0, warning: 0})
      :ok
      iex> Botica.Check.Result.health_status(%{error: 0, warning: 1})
      :degraded
      iex> Botica.Check.Result.health_status(%{error: 1, warning: 0})
      :fail
  """
  @spec health_status(Types.summary()) :: :ok | :degraded | :fail
  def health_status(summary)

  def health_status(%{error: error}) when error > 0 do
    :fail
  end

  def health_status(%{warning: warning}) when warning > 0 do
    :degraded
  end

  def health_status(%{error: 0, warning: 0}) do
    :ok
  end
end
