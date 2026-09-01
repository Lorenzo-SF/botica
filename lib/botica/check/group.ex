defmodule Botica.Check.Group do
  @moduledoc """
  Groups health checks into a unit that runs with a shared timeout.

  A group is a named collection of check definitions with execution
  options (`timeout_ms`, `parallel`). It reuses `Botica.Runner.Executor`
  for execution, so per-check timeouts and crash isolation apply.

  ## Example

      group = Botica.Check.Group.new(:db, [check_db, check_cache], timeout_ms: 2_000)

      results = Botica.Check.Group.run(group)
      # => %{db: %Check.Result{}, cache: %Check.Result{}}

  ## Result aggregation

  `as_result/2` reduces the group into a single summary result:
  - `:ok` — all checks passed (or no checks).
  - `:error` — at least one check failed.
  """

  alias Botica.Check.Result
  alias Botica.Runner.Executor
  alias Botica.Types

  @enforce_keys [:name, :checks]
  defstruct name: nil,
            checks: [],
            timeout_ms: 5_000,
            parallel: true

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          checks: [Types.check_def()],
          timeout_ms: non_neg_integer(),
          parallel: boolean()
        }

  @doc """
  Creates a new group.

  ## Options

    - `:timeout_ms` — global timeout for the whole group (default 5000).
    - `:parallel` — run checks in parallel (default `true`).
  """
  @spec new(atom() | String.t(), [Types.check_def()], keyword()) :: t()
  def new(name, checks, opts \\ []) when is_list(checks) do
    %__MODULE__{
      name: name,
      checks: checks,
      timeout_ms: Keyword.get(opts, :timeout_ms, 5_000),
      parallel: Keyword.get(opts, :parallel, true)
    }
  end

  @doc """
  Runs all checks in the group.

  Returns a map of `%{check_id => Result.t()}` (or `%{check_id => error}`
  for un-runnable groups).
  """
  @spec run(t()) :: %{Types.check_id() => Types.result() | term()}
  def run(%__MODULE__{checks: []}), do: %{}

  def run(%__MODULE__{checks: checks, parallel: true} = group) do
    config = %{app_name: "#{group.name}", checks: checks, options: []}

    case Executor.execute(config, timeout: group.timeout_ms) do
      {:ok, results} ->
        Map.new(results, fn result -> {result.id, result} end)

      {:error, reason} ->
        Map.new(checks, fn check -> {check.id, {:error, reason}} end)
    end
  end

  def run(%__MODULE__{checks: checks, parallel: false} = group) do
    config = %{app_name: "#{group.name}", checks: checks, options: []}

    case Executor.execute_sequential(config) do
      {:ok, results} ->
        Map.new(results, fn result -> {result.id, result} end)

      {:error, reason} ->
        Map.new(checks, fn check -> {check.id, {:error, reason}} end)
    end
  end

  @doc """
  Reduces the group results into a single `Botica.Check.Result`.

  `desired` is `:ok` (all checks must pass) or `:error` (any failure
  flips the summary to error). Returns a summary result whose id is the
  group name.
  """
  @spec as_result(t(), :ok | :error) :: Types.result()
  def as_result(%__MODULE__{name: name, checks: checks}, desired) do
    results = run(%__MODULE__{name: name, checks: checks, timeout_ms: 5_000, parallel: true})

    status =
      cond do
        results == %{} -> :ok
        Enum.all?(results, fn {_id, r} -> r.status == :ok end) -> :ok
        desired == :error and Enum.any?(results, fn {_id, r} -> r.status == :error end) -> :error
        true -> :error
      end

    Result.build(%{id: name, name: "#{name}", status: status}, status, group_message(results))
  end

  defp group_message(results) do
    total = map_size(results)
    failed = Enum.count(results, fn {_id, r} -> r.status != :ok end)

    if failed == 0 do
      "#{total} checks ok"
    else
      "#{failed}/#{total} checks failed"
    end
  end
end