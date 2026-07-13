defmodule Botica.Batteries.PostgreSQL do
  alias Arrea.Command
  alias Trebejo.Network
  alias Trebejo.Util

  @moduledoc """
  Predefined health check for PostgreSQL database connectivity.

  This module provides a ready-to-use check that verifies PostgreSQL
  is accessible. It prefers the `pg_isready` binary and falls back to
  a raw TCP port check (via `Trebejo.Network.port_open?/3`) when the
  binary is not installed.

  All command execution uses arg lists — never interpolated into
  shell strings — to prevent shell injection. Routed through
  `Trebejo.Util.run_cmd_legacy/3` for consistent timeout handling
  and structured errors.

  ## Usage

      config = %{
        app_name: "myapp",
        checks: [
          Botica.Batteries.PostgreSQL.check()
        ]
      }

  ## Options

  - `:host` - PostgreSQL host (default: "localhost")
  - `:port` - PostgreSQL port (default: 5432)
  - `:user` - PostgreSQL user (default: "postgres")
  - `:timeout` - Check timeout in ms (default: 5000)
  """

  @behaviour Botica.Check.Behaviour

  @impl true
  def check_def(opts \\ []) do
    host = Keyword.get(opts, :host, "localhost")
    port = Keyword.get(opts, :port, 5432)
    user = Keyword.get(opts, :user, "postgres")
    timeout = Keyword.get(opts, :timeout, 5000)

    %{
      id: :postgresql,
      name: "PostgreSQL",
      description: "Database server is running and accessible",
      priority: 1,
      tags: [:database, :critical],
      timeout: timeout,
      check: fn -> check_connection(host, port, user) end,
      fix: fn -> start_service() end,
      fix_command: "sudo systemctl start postgresql"
    }
  end

  @doc """
  Checks if PostgreSQL is ready to accept connections.

  Uses `pg_isready` when available. Falls back to a TCP probe on the
  configured port via `Trebejo.Network.port_open?/3` when the binary is
  not installed.
  """
  @spec check_connection(String.t(), non_neg_integer(), String.t()) :: Botica.Types.check_result()
  def check_connection(host, port, user) do
    cond do
      Command.command_exists?("pg_isready") ->
        check_via_pg_isready(host, port, user)

      Network.port_open?(host, port, timeout: 2_000) ->
        {:ok, "PostgreSQL port #{port} is open at #{host} (pg_isready not installed)"}

      true ->
        {:error, "PostgreSQL unreachable at #{host}:#{port} (no pg_isready, port closed)"}
    end
  end

  @doc """
  Attempts to start the PostgreSQL service via systemctl.
  """
  @spec start_service() :: Botica.Types.fix_result()
  def start_service do
    with :ok <- check_sudo_available(),
         :ok <- run_sudo_systemctl("start", "postgresql") do
      {:ok, "PostgreSQL service started"}
    else
      {:error, _} = err -> err
    end
  end

  # ── Private helpers ───────────────────────────────────────────────────────

  defp check_via_pg_isready(host, port, user) do
    case Util.run_cmd_legacy("pg_isready", ["-h", host, "-p", to_string(port), "-U", user],
           timeout: 5_000
         ) do
      {_output, 0} ->
        {:ok, "PostgreSQL is ready at #{host}:#{port}"}

      {output, code} ->
        {:error, "PostgreSQL not ready (exit #{code}): #{String.trim(output)}"}
    end
  end

  defp check_sudo_available do
    if Command.command_exists?("sudo") do
      case Util.run_cmd_legacy("sudo", ["-n", "true"]) do
        {_, 0} -> :ok
        _ -> {:error, "sudo requires a password or is not available. Configure NOPASSWD in sudoers."}
      end
    else
      {:error, "sudo not found in PATH"}
    end
  end

  defp run_sudo_systemctl(action, service) do
    case Util.run_cmd_legacy("sudo", ["systemctl", action, service], timeout: 30_000) do
      {_, 0} ->
        :ok

      {output, code} ->
        {:error, "systemctl #{action} #{service} failed (exit #{code}): #{String.trim(output)}"}
    end
  end
end
