defmodule Botica.Alerts.FormatTest do
  @moduledoc """
  Tests for Botica.Alerts.format_alert/2 (iter-042).
  """
  use ExUnit.Case, async: true

  alias Botica.Alerts

  describe "format_alert/2" do
    test "formats info alert" do
      assert Alerts.format_alert(:info, "Service started") == "[i] Service started"
    end

    test "formats warning alert" do
      assert Alerts.format_alert(:warning, "Disk 90% full") == "[!] Disk 90% full"
    end

    test "formats error alert" do
      assert Alerts.format_alert(:error, "Postgres down") == "[x] Postgres down"
    end

    test "formats critical alert" do
      assert Alerts.format_alert(:critical, "Out of memory") == "[X] Out of memory"
    end

    test "uses ? prefix for unknown severity" do
      assert Alerts.format_alert(:unknown, "test") == "[?] test"
    end
  end
end
