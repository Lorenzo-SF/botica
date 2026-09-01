defmodule Botica.DashboardTest do
  @moduledoc """
  Tests for `Botica.Dashboard` (HTTP requests against the dashboard).
  """

  use ExUnit.Case, async: false

  alias Botica.Dashboard

  @results [
    %{id: :database, name: "Database", status: :ok, message: "up", fix_command: nil},
    %{id: :disk, name: "Disk", status: :error, message: "full", fix_command: "clean"}
  ]

  setup do
    port = 45_000 + :rand.uniform(5_000)
    start_supervised!({Dashboard, port: port, provider: fn -> @results end})
    %{port: port}
  end

  defp get(port, path) do
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 2_000)
    :ok = :gen_tcp.send(socket, "GET #{path} HTTP/1.1\r\nHost: localhost\r\n\r\n")

    {:ok, response} = :gen_tcp.recv(socket, 0, 2_000)
    :gen_tcp.close(socket)
    response
  end

  test "GET / returns 200 with check states", %{port: port} do
    response = get(port, "/")
    assert response =~ "HTTP/1.1 200 OK"
    assert response =~ "Botica"
    assert response =~ "database"
    assert response =~ "disk"
    assert response =~ "error"
  end

  test "GET /health returns 503 when any check fails", %{port: port} do
    response = get(port, "/health")
    assert response =~ "HTTP/1.1 503 Service Unavailable"
    assert String.ends_with?(response, "\r\n\r\nfail")
  end

  test "GET /metrics returns Prometheus text", %{port: port} do
    response = get(port, "/metrics")
    assert response =~ "HTTP/1.1 200 OK"
    assert response =~ "# TYPE botica_check_status gauge"
    assert response =~ ~s(check="database",status="ok")
    assert response =~ ~s(check="disk",status="error")
  end

  test "GET /unknown returns 404", %{port: port} do
    response = get(port, "/nope")
    assert response =~ "HTTP/1.1 404 Not Found"
  end

  test "health is 200 when all checks pass" do
    port = 45_000 + :rand.uniform(5_000)
    name = :"dashboard_ok_#{System.unique_integer([:positive])}"
    ok_results = [%{id: :db, name: "DB", status: :ok, message: "up", fix_command: nil}]

    child_spec = %{
      id: name,
      start: {Dashboard, :start_link, [[port: port, provider: fn -> ok_results end, name: name]]}
    }

    start_supervised!(child_spec)

    response = get(port, "/health")
    assert response =~ "HTTP/1.1 200 OK"
    assert String.ends_with?(response, "\r\n\r\nok")
  end
end
