defmodule Botica.Doctor.ReporterTest do
  @moduledoc """
  Direct tests for `Botica.Doctor.Reporter` (usually reached via Doctor).
  """

  use ExUnit.Case, async: true

  alias Botica.Doctor.Reporter

  @results [
    %{id: :a, status: :ok, message: "a"},
    %{id: :b, status: :warning, message: "b"},
    %{id: :c, status: :error, message: "c"}
  ]

  test "summary/1 aggregates statuses" do
    summary = Reporter.summary(@results)
    assert summary.ok == 1
    assert summary.warning == 1
    assert summary.error == 1
    assert summary.total == 3
    refute summary.passed?
  end

  test "derive_status/1 returns :fail for errors, :degraded for warnings, :ok otherwise" do
    assert Reporter.derive_status(%{error: 1, warning: 0}) == :fail
    assert Reporter.derive_status(%{error: 0, warning: 1}) == :degraded
    assert Reporter.derive_status(%{error: 0, warning: 0}) == :ok
  end
end
