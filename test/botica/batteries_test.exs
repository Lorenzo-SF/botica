defmodule Botica.BatteriesTest do
  use ExUnit.Case, async: true

  alias Botica.Batteries.PostgreSQL
  alias Botica.Batteries.Redis
  alias Botica.Batteries.Memory
  alias Botica.Batteries.Disk

  describe "PostgreSQL.check_def/1" do
    test "returns a valid check definition" do
      check = PostgreSQL.check_def([])
      assert check.id == :postgresql
      assert check.name == "PostgreSQL"
      assert is_binary(check.description)
      assert check.priority == 1
      assert :database in check.tags
      assert :critical in check.tags
      assert is_function(check.check)
      assert is_function(check.fix)
    end

    test "accepts custom options" do
      check = PostgreSQL.check_def(host: "db.example.com", port: 5433)
      assert is_map(check)
    end
  end

  describe "Redis.check_def/1" do
    test "returns a valid check definition" do
      check = Redis.check_def([])
      assert check.id == :redis
      assert check.name == "Redis"
      assert is_binary(check.description)
      assert check.priority == 2
      assert :cache in check.tags
      assert :critical in check.tags
      assert is_function(check.check)
      assert is_function(check.fix)
    end
  end

  describe "Memory.check_def/1" do
    test "returns a valid check definition" do
      check = Memory.check_def([])
      assert check.id == :memory
      assert check.name == "Memory"
      assert is_binary(check.description)
      assert check.priority == 5
      assert :system in check.tags
      assert is_function(check.check)
    end

    test "accepts custom thresholds" do
      check = Memory.check_def(warning_threshold: 70, error_threshold: 90)
      assert is_map(check)
    end
  end

  describe "Disk.check_def/1" do
    test "returns a valid check definition" do
      check = Disk.check_def([])
      assert check.id == :disk
      assert check.name == "Disk"
      assert is_binary(check.description)
      assert check.priority == 4
      assert :system in check.tags
      assert is_function(check.check)
    end

    test "accepts custom path" do
      check = Disk.check_def(path: "/var/data")
      assert is_map(check)
    end
  end

  describe "Botica.Doctor.batteries/0" do
    test "returns list of all battery checks" do
      batteries = Botica.Doctor.batteries()
      assert length(batteries) == 4
      ids = Enum.map(batteries, & &1.id)
      assert :postgresql in ids
      assert :redis in ids
      assert :memory in ids
      assert :disk in ids
    end
  end

  describe "Botica.Runner.Sequencer" do
    alias Botica.Runner.Sequencer

    test "sort/1 sorts by priority then id" do
      checks = [
        %{id: :c, priority: 3},
        %{id: :a, priority: 1},
        %{id: :b, priority: 1}
      ]

      sorted = Sequencer.sort(checks)
      assert Enum.map(sorted, & &1.id) == [:a, :b, :c]
    end

    test "filter_by_tags/2 filters checks by tags" do
      checks = [
        %{id: :a, tags: [:critical]},
        %{id: :b, tags: [:database]},
        %{id: :c, tags: [:critical, :database]}
      ]

      filtered = Sequencer.filter_by_tags(checks, [:critical])
      assert length(filtered) == 2
      assert Enum.map(filtered, & &1.id) == [:a, :c]
    end

    test "filter_fixable/1 filters checks with fixes" do
      checks = [
        %{id: :a, fix: fn -> :ok end},
        %{id: :b, fix: nil},
        %{id: :c, fix: fn -> :ok end}
      ]

      filtered = Sequencer.filter_fixable(checks)
      assert length(filtered) == 2
    end
  end

  describe "Botica.Check.Result" do
    alias Botica.Check.Result

    test "build/3 creates a result map" do
      check = %{id: :test, name: "Test", fix_command: "fix it"}
      result = Result.build(check, :ok, "all good")
      assert result.id == :test
      assert result.name == "Test"
      assert result.status == :ok
      assert result.message == "all good"
      assert result.fix_command == "fix it"
    end

    test "to_status/1 converts result tuples" do
      assert Result.to_status({:ok, "msg"}) == {:ok, "msg"}
      assert Result.to_status({:warning, "msg"}) == {:warning, "msg"}
      assert Result.to_status({:error, "msg"}) == {:error, "msg"}
    end

    test "summarize/1 calculates correct counts" do
      results = [
        %{status: :ok},
        %{status: :ok},
        %{status: :warning},
        %{status: :error}
      ]

      summary = Result.summarize(results)
      assert summary.ok == 2
      assert summary.warning == 1
      assert summary.error == 1
      assert summary.total == 4
      assert summary.passed? == false
    end

    test "health_status/1 returns correct status" do
      assert Result.health_status(%{error: 0, warning: 0}) == :ok
      assert Result.health_status(%{error: 0, warning: 1}) == :degraded
      assert Result.health_status(%{error: 1, warning: 0}) == :fail
      assert Result.health_status(%{error: 1, warning: 1}) == :fail
    end
  end

  describe "Botica.Repair.Fixer" do
    alias Botica.Repair.Fixer

    test "fix_one/2 applies fix to single check" do
      config = %{
        app_name: "test",
        checks: [
          %{
            id: :check1,
            name: "Check 1",
            check: fn -> {:error, "bad"} end,
            fix: fn -> {:ok, "fixed"} end
          }
        ]
      }

      assert Fixer.fix_one(config, :check1) == {:ok, :applied}
    end

    test "fix_one/2 returns skipped for nil fix" do
      config = %{
        app_name: "test",
        checks: [
          %{
            id: :check1,
            name: "Check 1",
            check: fn -> {:error, "bad"} end,
            fix: nil
          }
        ]
      }

      assert Fixer.fix_one(config, :check1) == {:ok, :skipped}
    end

    test "fix_one/2 returns error for unknown check" do
      config = %{
        app_name: "test",
        checks: []
      }

      assert Fixer.fix_one(config, :unknown) == {:error, "check not found: :unknown"}
    end

    test "valid_fix?/1 validates fix functions" do
      assert Fixer.valid_fix?(fn -> :ok end) == true
      assert Fixer.valid_fix?(nil) == false
      assert Fixer.valid_fix?(fn _ -> :ok end) == false
    end
  end
end
