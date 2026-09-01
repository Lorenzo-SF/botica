defmodule Botica.SchedulerTest do
  @moduledoc """
  Tests for `Botica.Scheduler`.
  """

  use ExUnit.Case, async: false

  alias Botica.Check.Group
  alias Botica.Scheduler

  setup do
    :ets.delete_all_objects(:botica_scheduler_history)
    :ok
  end

  defp check(id) do
    %{
      id: id,
      name: Atom.to_string(id),
      description: "test check",
      priority: 1,
      tags: [:test],
      timeout: 1_000,
      check: fn -> {:ok, "#{id} ok"} end,
      fix: nil,
      fix_command: nil
    }
  end

  describe "add/3 schedule validation" do
    test "rejects missing schedule" do
      group = Group.new(:g1, [check(:c1)])
      assert {:error, :missing_schedule} = Scheduler.add(:s_missing, group, [])
    end

    test "accepts every/1 and cron/1" do
      group = Group.new(:g2, [check(:c2)])
      assert :ok = Scheduler.add(:s_every, group, every: {:minutes, 5})
      assert :ok = Scheduler.add(:s_cron, group, cron: "*/5 * * * *")
      assert :ok = Scheduler.add(:s_every_sec, group, every: {:seconds, 10})
      assert :ok = Scheduler.add(:s_every_ms, group, every: {:milliseconds, 100})
      assert :ok = Scheduler.add(:s_cron_star, group, cron: "* * * * *")
    end

    test "rejects malformed cron" do
      group = Group.new(:g3, [check(:c3)])
      assert {:error, {:invalid_cron, _}} = Scheduler.add(:s_bad, group, cron: "not-a-cron")
      assert {:error, {:invalid_cron, _}} = Scheduler.add(:s_bad2, group, cron: "*/5 * * *")
      assert {:error, {:invalid_cron, _}} = Scheduler.add(:s_bad3, group, cron: "*/61 * * * *")
      assert {:error, {:invalid_cron, _}} = Scheduler.add(:s_bad4, group, cron: "1 2 3 4 5")
      assert {:error, :invalid_cron} = Scheduler.add(:s_bad5, group, cron: 42)
    end

    test "rejects invalid runner" do
      assert {:error, {:invalid_runner, _}} = Scheduler.add(:s_nofun, "not a function", every: {:seconds, 1})
    end

    test "rejects invalid every interval" do
      group = Group.new(:g4, [check(:c4)])
      assert {:error, :invalid_interval} = Scheduler.add(:s_bad_interval, group, every: {:minutes, 0})
    end
  end

  describe "scheduled execution" do
    test "every: {:milliseconds, n} fires and records history" do
      parent = self()

      group = Group.new(:g_fast, [check(:c_fast)])
      assert :ok = Scheduler.add(:s_fast, group, every: {:milliseconds, 60}, max_history: 3)

      # Wait for at least one tick to land in history.
      wait_until(fn -> Scheduler.history(:s_fast) != [] end)

      [result | _] = Scheduler.history(:s_fast)
      assert {:ok, %{c_fast: %{status: :ok}}} = result

      # History is bounded by max_history.
      wait_until(fn -> length(Scheduler.history(:s_fast)) >= 2 end)
      assert length(Scheduler.history(:s_fast)) <= 3

      Scheduler.remove(:s_fast)
    end

    test "run_now/1 triggers immediately" do
      group = Group.new(:g_now, [check(:c_now)])
      assert :ok = Scheduler.add(:s_now, group, every: {:minutes, 60})

      assert :ok = Scheduler.run_now(:s_now)
      assert {:ok, %{c_now: %{status: :ok}}} = hd(Scheduler.history(:s_now))

      Scheduler.remove(:s_now)
    end

    test "run_now/1 on unknown schedule returns :not_found" do
      assert {:error, :not_found} = Scheduler.run_now(:s_unknown)
    end

    test "notify callback receives run results" do
      parent = self()
      group = Group.new(:g_notify, [check(:c_notify)])

      :ok =
        Scheduler.add(:s_notify, group,
          every: {:minutes, 60},
          notify: fn result -> send(parent, {:scheduled, result}) end
        )

      :ok = Scheduler.run_now(:s_notify)

      assert_receive {:scheduled, {:ok, %{c_notify: %{status: :ok}}}}, 1_000

      Scheduler.remove(:s_notify)
    end

    test "runner crash is captured as {:error, ...} and still recorded" do
      parent = self()

      :ok =
        Scheduler.add(:s_crash, fn -> raise "boom" end,
          every: {:minutes, 60},
          notify: fn result -> send(parent, {:scheduled, result}) end
        )

      :ok = Scheduler.run_now(:s_crash)
      assert_receive {:scheduled, {:error, {:runner_crashed, msg}}}, 1_000
      assert msg =~ "boom"
      assert {:error, _} = hd(Scheduler.history(:s_crash))

      Scheduler.remove(:s_crash)
    end
  end

  describe "remove/1 and all/0" do
    test "remove/1 stops the schedule" do
      group = Group.new(:g_rm, [check(:c_rm)])
      assert :ok = Scheduler.add(:s_rm, group, every: {:milliseconds, 30}, max_history: 2)

      assert :ok = Scheduler.remove(:s_rm)
      before = length(Scheduler.history(:s_rm))

      Process.sleep(120)
      after_length = length(Scheduler.history(:s_rm))
      assert before == after_length
    end

    test "all/0 lists registered schedules" do
      group = Group.new(:g_all, [check(:c_all)])
      assert :ok = Scheduler.add(:s_all_a, group, every: {:minutes, 5})
      assert :ok = Scheduler.add(:s_all_b, group, cron: "*/10 * * * *")

      schedules = Scheduler.all()
      assert {:s_all_a, {:every, {:minutes, 5}}} in schedules
      assert {:s_all_b, {:cron, 10}} in schedules

      Scheduler.remove(:s_all_a)
      Scheduler.remove(:s_all_b)
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp wait_until(fun, attempts \\ 50) do
    if fun.() do
      :ok
    else
      if attempts > 0 do
        Process.sleep(10)
        wait_until(fun, attempts - 1)
      else
        flunk("condition not met in time")
      end
    end
  end
end
