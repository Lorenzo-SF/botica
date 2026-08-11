defmodule Botica.Check.GroupTest do
  use ExUnit.Case, async: false

  alias Botica.Check.Group

  defp ok_check(id, name \\ nil) do
    %{id: id, name: name || "#{id}", priority: 1, check: fn -> {:ok, "ok"} end}
  end

  defp error_check(id) do
    %{id: id, name: "#{id}", priority: 1, check: fn -> {:error, "nope"} end}
  end

  defp slow_check(ms) do
    %{id: :slow, name: "slow", priority: 1, check: fn -> Process.sleep(ms); {:ok, "slow done"} end}
  end

  test "new/3 sets defaults" do
    group = Group.new(:web, [ok_check(:a)])
    assert group.name == :web
    assert group.timeout_ms == 5_000
    assert group.parallel == true
  end

  test "run/1 returns map of results keyed by check id" do
    group = Group.new(:web, [ok_check(:a), ok_check(:b)])
    results = Group.run(group)
    assert map_size(results) == 2
    assert %{status: :ok} = Map.fetch!(results, :a)
    assert %{status: :ok} = Map.fetch!(results, :b)
  end

  test "run/1 with a failing check keeps other results" do
    group = Group.new(:web, [ok_check(:a), error_check(:b)])
    results = Group.run(group)
    assert %{status: :ok} = Map.fetch!(results, :a)
    assert %{status: :error} = Map.fetch!(results, :b)
  end

  test "empty group runs to empty map" do
    assert Group.run(Group.new(:empty, [])) == %{}
  end

  test "as_result/2 returns :ok when all checks pass" do
    group = Group.new(:web, [ok_check(:a), ok_check(:b)])
    assert %{id: :web, status: :ok} = Group.as_result(group, :ok)
  end

  test "as_result/2 returns :error when a check fails" do
    group = Group.new(:web, [ok_check(:a), error_check(:b)])
    assert %{id: :web, status: :error, message: "1/2 checks failed"} = Group.as_result(group, :ok)
  end

  test "sequential mode runs checks one by one" do
    group = Group.new(:web, [ok_check(:a), ok_check(:b)], parallel: false)
    results = Group.run(group)
    assert map_size(results) == 2
  end
end