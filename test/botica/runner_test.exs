defmodule Botica.RunnerExecutorTest do
  use ExUnit.Case, async: true

  alias Botica.Runner.Executor

  describe "execute/1" do
    test "returns error for invalid config (not a map)" do
      assert {:error, "config must be a map"} = Executor.execute("not a map")
    end

    test "returns error for missing checks" do
      config = %{app_name: "test"}
      assert {:error, "config.checks must be a list"} = Executor.execute(config)
    end

    test "returns error for invalid app_name" do
      config = %{app_name: 123, checks: []}
      assert {:error, "config.app_name must be a string"} = Executor.execute(config)
    end
  end

  describe "execute/2 with options" do
    test "accepts timeout option" do
      config = %{
        app_name: "test",
        checks: [
          %{
            id: :check1,
            name: "Check 1",
            description: "",
            priority: 1,
            check: fn -> {:ok, "ok"} end,
            fix: fn -> :skipped end
          }
        ]
      }

      assert {:ok, [_]} = Executor.execute(config, timeout: 5000)
    end

    test "per-check timeout overrides global timeout" do
      config = %{
        app_name: "test",
        checks: [
          %{
            id: :slow,
            name: "Slow",
            description: "",
            priority: 1,
            timeout: 50,
            check: fn ->
              Process.sleep(100)
              {:ok, "done"}
            end,
            fix: fn -> :skipped end
          }
        ]
      }

      assert {:ok, [result]} = Executor.execute(config, timeout: 5000)
      assert result.status == :error
      assert result.message =~ "timeout"
    end
  end

  describe "execute_sequential/1" do
    test "executes checks in sorted order" do
      config = %{
        app_name: "test",
        checks: [
          %{
            id: :first,
            name: "First",
            description: "",
            priority: 2,
            check: fn -> {:ok, "first"} end,
            fix: fn -> :skipped end
          },
          %{
            id: :second,
            name: "Second",
            description: "",
            priority: 1,
            check: fn -> {:ok, "second"} end,
            fix: fn -> :skipped end
          }
        ]
      }

      assert {:ok, results} = Executor.execute_sequential(config)
      # Sequential still sorts by priority
      assert Enum.map(results, & &1.id) == [:second, :first]
    end

    test "handles exceptions in sequential mode" do
      config = %{
        app_name: "test",
        checks: [
          %{
            id: :boom,
            name: "Boom",
            description: "",
            priority: 1,
            check: fn -> raise "oops" end,
            fix: fn -> :skipped end
          }
        ]
      }

      assert {:ok, [result]} = Executor.execute_sequential(config)
      assert result.status == :error
      assert result.message =~ "exception"
    end
  end
end

defmodule Botica.RunnerSequencerTest do
  use ExUnit.Case, async: true

  alias Botica.Runner.Sequencer

  describe "sort/1" do
    test "sorts checks by priority ascending" do
      checks = [
        %{id: :z, priority: 10},
        %{id: :a, priority: 1},
        %{id: :m, priority: 5}
      ]

      sorted = Sequencer.sort(checks)
      assert Enum.map(sorted, & &1.id) == [:a, :m, :z]
    end

    test "sorts by id when priority is equal" do
      checks = [
        %{id: :z, priority: 1},
        %{id: :a, priority: 1},
        %{id: :m, priority: 1}
      ]

      sorted = Sequencer.sort(checks)
      assert Enum.map(sorted, & &1.id) == [:a, :m, :z]
    end
  end

  describe "filter_by_tags/2" do
    test "returns empty list when no matches" do
      checks = [
        %{id: :a, tags: [:critical]}
      ]

      filtered = Sequencer.filter_by_tags(checks, [:database])
      assert filtered == []
    end

    test "matches checks that have any of the given tags" do
      checks = [
        %{id: :a, tags: [:database]},
        %{id: :b, tags: [:critical]},
        %{id: :c, tags: [:both]}
      ]

      filtered = Sequencer.filter_by_tags(checks, [:critical, :database])
      # a has :database, b has :critical, c has :both (no :critical or :database)
      assert length(filtered) == 2
    end
  end

  describe "filter_fixable/1" do
    test "excludes checks with nil fix" do
      checks = [
        %{id: :a, fix: nil},
        %{id: :b, fix: fn -> :ok end}
      ]

      filtered = Sequencer.filter_fixable(checks)
      assert length(filtered) == 1
      assert hd(filtered).id == :b
    end
  end

  describe "group_by_tags/1" do
    test "groups checks by tags" do
      checks = [
        %{id: :a, tags: [:a_tag]},
        %{id: :b, tags: [:b_tag]},
        %{id: :c, tags: [:a_tag]}
      ]

      grouped = Sequencer.group_by_tags(checks)
      assert length(grouped[:a_tag]) == 2
      assert length(grouped[:b_tag]) == 1
    end

    test "handles checks with no tags" do
      checks = [
        %{id: :a, tags: []},
        %{id: :b, tags: [:tag]}
      ]

      grouped = Sequencer.group_by_tags(checks)
      assert grouped == %{tag: [%{id: :b, tags: [:tag]}]}
    end
  end
end
