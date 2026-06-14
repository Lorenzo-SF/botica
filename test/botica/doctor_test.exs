defmodule Botica.DoctorTest do
  use ExUnit.Case, async: true

  alias Botica.Doctor

  describe "run/1" do
    test "returns {:ok, results} for passing checks" do
      config = passing_config()
      assert {:ok, [result]} = Doctor.run(config)
      assert result.status == :ok
      assert result.id == :a
    end

    test "returns {:ok, results} even with failing checks" do
      config = failing_config()
      assert {:ok, [result]} = Doctor.run(config)
      assert result.status == :error
    end

    test "returns {:ok, results} for warning checks" do
      config = warning_config()
      assert {:ok, [result]} = Doctor.run(config)
      assert result.status == :warning
    end

    test "captures exceptions as errors" do
      config = %{
        app_name: "T",
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

      assert {:ok, [result]} = Doctor.run(config)
      assert result.status == :error
      assert String.contains?(result.message, "exception")
    end

    test "runs checks in parallel" do
      checks =
        Enum.map(1..5, fn i ->
          %{
            id: {:check, i},
            name: "Check #{i}",
            description: "",
            priority: i,
            check: fn ->
              Process.sleep(50)
              {:ok, "ok"}
            end,
            fix: fn -> :skipped end
          }
        end)

      config = %{app_name: "T", checks: checks}

      assert {:ok, results} = Doctor.run(config)
      assert length(results) == 5
      assert Enum.all?(results, &(&1.status == :ok))
    end

    test "sorts checks by priority" do
      config = %{
        app_name: "T",
        checks: [
          %{
            id: :second,
            name: "Second",
            description: "",
            priority: 2,
            check: fn -> {:ok, "second"} end,
            fix: fn -> :skipped end
          },
          %{
            id: :first,
            name: "First",
            description: "",
            priority: 1,
            check: fn -> {:ok, "first"} end,
            fix: fn -> :skipped end
          }
        ]
      }

      assert {:ok, results} = Doctor.run(config)
      assert Enum.map(results, & &1.name) == ["First", "Second"]
    end

    test "validates config.checks is a list" do
      config = %{app_name: "T"}

      assert {:error, "config.checks must be a list"} = Doctor.run(config)
    end

    test "validates config.app_name is a string" do
      config = %{app_name: 123, checks: []}

      assert {:error, "config.app_name must be a string"} = Doctor.run(config)
    end
  end

  describe "run/2 with timeout" do
    test "respects per-check timeout" do
      config = %{
        app_name: "T",
        checks: [
          %{
            id: :slow,
            name: "Slow",
            description: "",
            priority: 1,
            timeout: 100,
            check: fn ->
              Process.sleep(200)
              {:ok, "done"}
            end,
            fix: fn -> :skipped end
          }
        ]
      }

      assert {:ok, [result]} = Doctor.run(config, timeout: 5000)
      assert result.status == :error
      assert String.contains?(result.message, "timeout")
    end
  end

  describe "summary/1" do
    test "returns correct counts" do
      results = [
        %{status: :ok},
        %{status: :ok},
        %{status: :warning},
        %{status: :error}
      ]

      summary = Doctor.summary(results)

      assert summary.ok == 2
      assert summary.warning == 1
      assert summary.error == 1
      assert summary.total == 4
      assert summary.passed? == false
    end

    test "passed? is true when no errors" do
      results = [
        %{status: :ok},
        %{status: :warning}
      ]

      summary = Doctor.summary(results)
      assert summary.passed? == true
    end

    test "passed? is false when errors exist" do
      results = [
        %{status: :ok},
        %{status: :error}
      ]

      summary = Doctor.summary(results)
      assert summary.passed? == false
    end
  end

  describe "health_check/1" do
    test "returns :ok status when all checks pass" do
      config = passing_config()
      result = Doctor.health_check(config)

      assert result.status == :ok
      assert result.summary.passed? == true
    end

    test "returns :fail status when any check errors" do
      config = failing_config()
      result = Doctor.health_check(config)

      assert result.status == :fail
      assert result.summary.error == 1
    end

    test "returns :degraded status when any check warns but none error" do
      config = warning_config()
      result = Doctor.health_check(config)

      assert result.status == :degraded
      assert result.summary.warning == 1
    end

    test "returns error when config is invalid" do
      config = %{app_name: "T"}

      result = Doctor.health_check(config)
      assert result.status == :fail
      assert result.error == "config.checks must be a list"
    end
  end

  describe "fix/1" do
    test "runs fix functions for failed checks" do
      config = %{
        app_name: "T",
        checks: [
          %{
            id: :failing,
            name: "Failing",
            description: "",
            priority: 1,
            check: fn -> {:error, "something wrong"} end,
            fix: fn -> {:ok, "fixed!"} end
          }
        ]
      }

      assert {:ok, report} = Doctor.fix(config)
      assert report.applied == [:failing]
      assert report.failed == []
      assert report.skipped == []
    end

    test "skips fixes when no errors" do
      config = passing_config()

      assert {:ok, report} = Doctor.fix(config)
      assert report.applied == []
      assert report.skipped == [:a]
    end

    test "continues execution when fix returns error" do
      config = %{
        app_name: "T",
        checks: [
          %{
            id: :fail1,
            name: "Fail1",
            description: "",
            priority: 1,
            check: fn -> {:error, "problem"} end,
            fix: fn -> {:error, "can't fix"} end
          },
          %{
            id: :fail2,
            name: "Fail2",
            description: "",
            priority: 2,
            check: fn -> {:error, "another problem"} end,
            fix: fn -> {:ok, "fixed"} end
          }
        ]
      }

      assert {:ok, report} = Doctor.fix(config)
      assert report.applied == [:fail2]
      assert report.failed == [{:fail1, "can't fix"}]
    end

    test "only runs fixes for checks that failed" do
      # Use a unique agent name to avoid conflicts
      agent_name = :fixes_agent_test_only_runs

      on_exit(fn ->
        # Only stop if it exists
        if Process.whereis(agent_name) do
          Agent.stop(agent_name, :normal)
        end
      end)

      config = %{
        app_name: "T",
        checks: [
          %{
            id: :ok_check,
            name: "OK",
            description: "",
            priority: 1,
            check: fn -> {:ok, "good"} end,
            fix: fn -> Agent.update(agent_name, &[:ok_check | &1]) end
          },
          %{
            id: :failing,
            name: "Failing",
            description: "",
            priority: 2,
            check: fn -> {:error, "problem"} end,
            fix: fn -> Agent.update(agent_name, &[:failing | &1]) end
          },
          %{
            id: :ok_check2,
            name: "OK2",
            description: "",
            priority: 3,
            check: fn -> {:ok, "also good"} end,
            fix: fn -> Agent.update(agent_name, &[:ok_check2 | &1]) end
          }
        ]
      }

      # Start agent only for this test
      {:ok, _agent} = Agent.start_link(fn -> [] end, name: agent_name)

      assert {:ok, _report} = Doctor.fix(config)
      # Only :failing fix should have been called (since only it failed)
      fixes_run = Agent.get(agent_name, & &1)
      assert fixes_run == [:failing]
    end

    test "skips checks with nil fix" do
      config = %{
        app_name: "T",
        checks: [
          %{
            id: :no_fix,
            name: "No Fix",
            description: "",
            priority: 1,
            check: fn -> {:error, "cannot fix"} end,
            fix: nil
          }
        ]
      }

      assert {:ok, report} = Doctor.fix(config)
      assert report.applied == []
      assert report.skipped == [:no_fix]
    end
  end

  describe "validate/1" do
    test "returns :ok for valid config" do
      config = %{app_name: "test", checks: []}
      assert Doctor.validate(config) == :ok
    end

    test "returns error for missing checks" do
      config = %{app_name: "test"}
      assert Doctor.validate(config) == {:error, "config.checks must be a list"}
    end

    test "returns error for missing app_name" do
      config = %{checks: []}
      assert Doctor.validate(config) == {:error, "config.app_name must be a string"}
    end

    test "returns error for invalid app_name type" do
      config = %{app_name: 123, checks: []}
      assert Doctor.validate(config) == {:error, "config.app_name must be a string"}
    end
  end

  describe "batteries/0" do
    test "returns list of predefined checks" do
      batteries = Doctor.batteries()
      assert is_list(batteries)
      assert length(batteries) == 4

      ids = Enum.map(batteries, & &1.id)
      assert :postgresql in ids
      assert :redis in ids
      assert :memory in ids
      assert :disk in ids
    end

    test "battery checks have required fields" do
      battery = Botica.Batteries.PostgreSQL.check_def([])

      assert battery.id == :postgresql
      assert is_binary(battery.name)
      assert is_binary(battery.description)
      assert is_integer(battery.priority)
      assert is_list(battery.tags)
      assert is_function(battery.check, 0)
      assert is_function(battery.fix, 0) or battery.fix == nil
    end
  end

  describe "sort_checks/1" do
    test "sorts by priority" do
      checks = [
        %{id: :c, priority: 3},
        %{id: :a, priority: 1},
        %{id: :b, priority: 2}
      ]

      sorted = Doctor.sort_checks(checks)
      assert Enum.map(sorted, & &1.id) == [:a, :b, :c]
    end

    test "sorts by id when priority is equal" do
      checks = [
        %{id: :b, priority: 1},
        %{id: :a, priority: 1}
      ]

      sorted = Doctor.sort_checks(checks)
      assert Enum.map(sorted, & &1.id) == [:a, :b]
    end
  end

  defp passing_config do
    %{
      app_name: "T",
      checks: [
        %{
          id: :a,
          name: "A",
          description: "",
          priority: 1,
          check: fn -> {:ok, "ok"} end,
          fix: fn -> :skipped end
        }
      ]
    }
  end

  defp failing_config do
    %{
      app_name: "T",
      checks: [
        %{
          id: :fail,
          name: "Fail",
          description: "",
          priority: 1,
          check: fn -> {:error, "failed"} end,
          fix: fn -> {:ok, "fixed"} end
        }
      ]
    }
  end

  defp warning_config do
    %{
      app_name: "T",
      checks: [
        %{
          id: :warn,
          name: "Warn",
          description: "",
          priority: 1,
          check: fn -> {:warning, "warning message"} end,
          fix: fn -> :skipped end
        }
      ]
    }
  end
end
