defmodule Botica.AlertsTest do
  @moduledoc """
  Tests for `Botica.Alerts`.
  """

  use ExUnit.Case, async: false

  alias Botica.Alerts

  # Subscriber that always errors (must not crash the tracker).
  defmodule BrokenSubscriber do
    @behaviour Alerts.Subscriber

    @impl true
    def notify(_kind, _result), do: {:error, :boom}
  end

  setup do
    :ets.delete_all_objects(:botica_alerts_state)

    # Clear subscribers between tests by unsubscribing (best effort) and
    # re-subscribing a fresh capturing subscriber per test.
    :ok = Alerts.subscribe(capturing_subscriber(self()))
    :ok
  end

  defp capturing_subscriber(pid) do
    fn kind, result -> send(pid, {:alert, kind, result}) end
  end

  defp result(id, status) do
    %{id: id, name: Atom.to_string(id), status: status, message: "#{status}", fix_command: nil}
  end

  describe "failure alerting" do
    test "notifies when a check fails threshold (3) consecutive times" do
      for _ <- 1..2 do
        Alerts.track(:db_check, result(:db_check, :error))
        refute_receive {:alert, _, _}, 50
      end

      Alerts.track(:db_check, result(:db_check, :error))

      assert_receive {:alert, :failed, %{id: :db_check, status: :error}}, 500
      assert Alerts.failures(:db_check) == 3
    end

    test "does not re-notify on every subsequent failure" do
      for _ <- 1..3 do
        Alerts.track(:db_check, result(:db_check, :error))
      end

      assert_receive {:alert, :failed, _}, 500

      Alerts.track(:db_check, result(:db_check, :error))
      refute_receive {:alert, _, _}, 100
      assert Alerts.failures(:db_check) == 4
    end

    test "threshold is configurable via start options" do
      # Second tracker with threshold 1 under a custom name.
      name = :"alerts_t1_#{System.unique_integer([:positive])}"

      child = %{
        id: name,
        start: {Alerts, :start_link, [[threshold: 1, name: name]]}
      }

      start_supervised!(child)

      GenServer.call(name, {:subscribe, capturing_subscriber(self())})
      GenServer.call(name, {:track, :api_check, result(:api_check, :error)})

      assert_receive {:alert, :failed, %{id: :api_check}}, 500
      assert Alerts.failures(:api_check) == 1
    end
  end

  describe "recovery" do
    test "notifies :recovered when a check recovers after failures" do
      for _ <- 1..3 do
        Alerts.track(:web_check, result(:web_check, :error))
      end

      assert_receive {:alert, :failed, _}, 500

      Alerts.track(:web_check, result(:web_check, :ok))

      assert_receive {:alert, :recovered, %{id: :web_check, status: :ok}}, 500
      assert Alerts.failures(:web_check) == 0
    end

    test "does not notify :recovered if the check never failed" do
      Alerts.track(:clean_check, result(:clean_check, :ok))
      refute_receive {:alert, _, _}, 100
    end

    test "warning status does not count as failure nor recovery" do
      Alerts.track(:warn_check, result(:warn_check, :warning))
      assert Alerts.failures(:warn_check) == 0
      refute_receive {:alert, _, _}, 100
    end
  end

  describe "reset/1" do
    test "reset clears the failure counter" do
      for _ <- 1..2 do
        Alerts.track(:mem_check, result(:mem_check, :error))
      end

      assert Alerts.failures(:mem_check) == 2
      :ok = Alerts.reset(:mem_check)
      assert Alerts.failures(:mem_check) == 0
    end
  end

  describe "subscriber robustness" do
    test "subscriber errors do not crash the tracker" do
      :ok = Alerts.subscribe(BrokenSubscriber)

      for _ <- 1..3 do
        Alerts.track(:broken_check, result(:broken_check, :error))
      end

      assert_receive {:alert, :failed, _}, 500
      assert Alerts.failures(:broken_check) == 3
    end
  end
end
