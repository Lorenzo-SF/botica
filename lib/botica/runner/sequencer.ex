defmodule Botica.Runner.Sequencer do
  @moduledoc """
  Sorts and sequences checks based on their priority and dependencies.

  Checks are sorted by priority (lower number = higher priority = runs first).
  Within the same priority, checks are ordered by their id to ensure
  deterministic execution order.
  """

  alias Botica.Types

  @doc """
  Sorts checks by priority.

  Lower priority values run first. When priorities are equal,
  checks are ordered by their id for determinism.

  ## Examples

      iex> checks = [
      ...>   %{id: :b, name: \"B\", priority: 2},
      ...>   %{id: :a, name: \"A\", priority: 1},
      ...>   %{id: :c, name: \"C\", priority: 1}
      ...> ]
      iex> Botica.Runner.Sequencer.sort(checks)
      [
        %{id: :a, name: \"A\", priority: 1},
        %{id: :c, name: \"C\", priority: 1},
        %{id: :b, name: \"B\", priority: 2}
      ]
  """
  @spec sort([Types.check_def()]) :: [Types.check_def()]
  def sort(checks) do
    Enum.sort_by(checks, fn check -> {check.priority, check.id} end)
  end

  @doc """
  Filters checks by tags.

  ## Examples

      iex> checks = [
      ...>   %{id: :a, name: \"A\", tags: [:critical]},
      ...>   %{id: :b, name: \"B\", tags: [:database]},
      ...>   %{id: :c, name: \"C\", tags: [:critical, :database]}
      ...> ]
      iex> Botica.Runner.Sequencer.filter_by_tags(checks, [:critical])
      [%{id: :a, name: \"A\", tags: [:critical]}, %{id: :c, name: \"C\", tags: [:critical, :database]}]
  """
  @spec filter_by_tags([Types.check_def()], [atom()]) :: [Types.check_def()]
  def filter_by_tags(checks, tags) when is_list(tags) do
    Enum.filter(checks, fn check ->
      check_tags = Map.get(check, :tags, [])
      Enum.any?(tags, &(&1 in check_tags))
    end)
  end

  @doc """
  Filters checks that have a fix defined.

  ## Examples

      iex> checks = [
      ...>   %{id: :a, fix: fn -> :ok end},
      ...>   %{id: :b, fix: nil},
      ...>   %{id: :c, fix: fn -> :ok end}
      ...> ]
      iex> Botica.Runner.Sequencer.filter_fixable(checks)
      [%{id: :a, fix: _}, %{id: :c, fix: _}]
  """
  @spec filter_fixable([Types.check_def()]) :: [Types.check_def()]
  def filter_fixable(checks) do
    Enum.filter(checks, fn check ->
      check.fix != nil
    end)
  end

  @doc """
  Groups checks by their tags.

  ## Examples

      iex> checks = [
      ...>   %{id: :a, tags: [:critical]},
      ...>   %{id: :b, tags: [:database]},
      ...>   %{id: :c, tags: [:critical]}
      ...> ]
      iex> Botica.Runner.Sequencer.group_by_tags(checks)
      %{critical: [%{id: :a, tags: [:critical]}, %{id: :c, tags: [:critical]}], database: [%{id: :b, tags: [:database]}]}
  """
  @spec group_by_tags([Types.check_def()]) :: %{atom() => [Types.check_def()]}
  def group_by_tags(checks) do
    checks
    |> Enum.flat_map(fn check ->
      tags = Map.get(check, :tags, [])
      Enum.map(tags, &{&1, check})
    end)
    |> Enum.group_by(fn {tag, _} -> tag end, fn {_, check} -> check end)
  end
end
