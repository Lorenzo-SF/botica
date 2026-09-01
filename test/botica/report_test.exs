defmodule Botica.ReportTest do
  @moduledoc """
  Tests for `Botica.Report` (Prometheus / OTel exporters).
  """

  use ExUnit.Case, async: true

  alias Botica.Report

  @results [
    %{id: :database, name: "Database", status: :ok, message: "up", fix_command: nil},
    %{id: :memory, name: "Memory", status: :warning, message: "low", fix_command: nil},
    %{id: :disk, name: "Disk", status: :error, message: "full", fix_command: "clean"}
  ]

  describe "prometheus_text/1" do
    test "emits HELP and TYPE header lines" do
      text = Report.prometheus_text(@results)

      assert text =~ "# HELP botica_check_status"
      assert text =~ "# TYPE botica_check_status gauge"
    end

    test "emits one gauge line per check with status label" do
      text = Report.prometheus_text(@results)

      assert text =~ ~s(botica_check_status{check="database",status="ok"} 1)
      assert text =~ ~s(botica_check_status{check="memory",status="warning"} 1)
      assert text =~ ~s(botica_check_status{check="disk",status="error"} 1)
    end

    test "empty results produce just the header" do
      text = Report.prometheus_text([])
      assert text =~ "# TYPE botica_check_status gauge"
      refute text =~ ~r/botica_check_status\{/
    end

    test "escapes label values (quotes, backslashes, newlines)" do
      tricky = [%{id: :weird, name: "Weird", status: :ok, message: "x", fix_command: nil}]
      text = Report.prometheus_text(tricky)
      assert text =~ ~s(check="weird",status="ok")
    end

    test "output ends with trailing newline (Prometheus spec)" do
      assert String.ends_with?(Report.prometheus_text(@results), "\n")
    end
  end

  describe "otel_export/1" do
    test "emits one telemetry event per check and returns :ok" do
      parent = self()
      handler_id = "report-test-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        handler_id,
        [:botica, :report, :otel],
        fn event, measurements, metadata, _ ->
          send(parent, {:otel, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert :ok = Report.otel_export(@results)

      received =
        for _ <- @results do
          receive do
            {:otel, [:botica, :report, :otel], %{value: 1}, meta} -> meta
          after
            500 -> flunk("missing otel telemetry event")
          end
        end

      checks = Enum.map(received, & &1.check)
      assert :database in checks
      assert :memory in checks
      assert :disk in checks
    end

    test "works with empty results" do
      assert :ok = Report.otel_export([])
    end
  end

  describe "summary/1 and health_status/1" do
    test "summarize aggregates statuses" do
      summary = Report.summary(@results)
      assert summary.ok == 1
      assert summary.warning == 1
      assert summary.error == 1
      assert summary.total == 3
      refute summary.passed?
    end

    test "health_status derives :fail when any error present" do
      assert Report.health_status(Report.summary(@results)) == :fail
      assert Report.health_status(%{ok: 2, warning: 1, error: 0}) == :degraded
      assert Report.health_status(%{ok: 3, warning: 0, error: 0}) == :ok
    end
  end
end
