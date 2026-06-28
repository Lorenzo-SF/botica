defmodule Botica.Batteries.PostgreSQL do
  @moduledoc """
  Predefined health check for PostgreSQL database connectivity.

  This module provides a ready-to-use check that verifies PostgreSQL
  is accessible using the `pg_isready` command.

  ## Installation

  Requires `pg_isready` to be available in the system PATH.

  ## Usage

      config = %{
        app_name: \"myapp\",
        checks: [
          Botica.Batteries.PostgreSQL.check()
        ]
      }

  ## Options

  - `:host` - PostgreSQL host (default: \"localhost\")
  - `:port` - PostgreSQL port (default: 5432)
  - `:user` - PostgreSQL user (default: \"postgres\")
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
  """
  @spec check_connection(String.t(), non_neg_integer(), String.t()) :: Botica.Types.check_result()
  def check_connection(host, port, user) do
    args = ["-h", host, "-p", to_string(port), "-U", user]

    case System.cmd("pg_isready", args, stderr_to_stdout: true) do
      {_output, 0} ->
        {:ok, "PostgreSQL is ready at #{host}:#{port}"}

      {output, _} ->
        {:error, "PostgreSQL not ready: #{String.trim(output)}"}
    end
  rescue
    error ->
      {:error, "Failed to check PostgreSQL: #{Exception.message(error)}"}
  end

  @doc """
  Attempts to start the PostgreSQL service.
  """
  @spec start_service() :: Botica.Types.fix_result()
  def start_service do
    with {:ok, _} <- can_sudo?(),
         {_, 0} <-
           System.cmd("sudo", ["systemctl", "start", "postgresql"], stderr_to_stdout: true) do
      {:ok, "PostgreSQL service started"}
    else
      {:error, reason} -> {:error, reason}
      {output, _} -> {:error, "Failed to start PostgreSQL: #{String.trim(output)}"}
    end
  rescue
    error ->
      {:error, "Failed to start PostgreSQL: #{Exception.message(error)}"}
  end

  defp can_sudo? do
    case System.cmd("sudo", ["-n", "true"], stderr_to_stdout: true) do
      {_, 0} ->
        {:ok, :can_sudo}

      {_, _} ->
        {:error, "sudo requires a password or is not available. Configure NOPASSWD in sudoers."}
    end
  rescue
    _ -> {:error, "sudo not found or not available"}
  end
end
