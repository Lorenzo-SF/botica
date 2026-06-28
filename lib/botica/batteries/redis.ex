defmodule Botica.Batteries.Redis do
  @moduledoc """
  Predefined health check for Redis cache server.

  This module provides a ready-to-use check that verifies Redis
  is accessible using the `redis-cli` command.

  ## Installation

  Requires `redis-cli` to be available in the system PATH.

  ## Usage

      config = %{
        app_name: \"myapp\",
        checks: [
          Botica.Batteries.Redis.check()
        ]
      }

  ## Options

  - `:host` - Redis host (default: \"localhost\")
  - `:port` - Redis port (default: 6379)
  - `:timeout` - Check timeout in ms (default: 5000)
  """

  @behaviour Botica.Check.Behaviour

  @impl true
  def check_def(opts \\ []) do
    host = Keyword.get(opts, :host, "localhost")
    port = Keyword.get(opts, :port, 6379)
    timeout = Keyword.get(opts, :timeout, 5000)

    %{
      id: :redis,
      name: "Redis",
      description: "Cache server is running and responding",
      priority: 2,
      tags: [:cache, :critical],
      timeout: timeout,
      check: fn -> check_connection(host, port) end,
      fix: fn -> start_service() end,
      fix_command: "sudo systemctl start redis-server"
    }
  end

  @doc """
  Checks if Redis is responding to PING.
  """
  @spec check_connection(String.t(), non_neg_integer()) :: Botica.Types.check_result()
  def check_connection(host, port) do
    args = ["-h", host, "-p", to_string(port), "ping"]

    case System.cmd("redis-cli", args, stderr_to_stdout: true) do
      {"PONG", 0} ->
        {:ok, "Redis is responding at #{host}:#{port}"}

      {output, _} ->
        {:error, "Redis not responding: #{String.trim(output)}"}
    end
  rescue
    error ->
      {:error, "Failed to check Redis: #{Exception.message(error)}"}
  end

  @doc """
  Attempts to start the Redis service.
  """
  @spec start_service() :: Botica.Types.fix_result()
  def start_service do
    case can_sudo?() do
      {:ok, _} ->
        commands = [
          ["sudo", "systemctl", "start", "redis-server"],
          ["sudo", "systemctl", "start", "redis"]
        ]

        results =
          Enum.map(commands, fn cmd ->
            System.cmd(hd(cmd), tl(cmd), stderr_to_stdout: true)
          end)

        case Enum.find(results, fn {_, exit_code} -> exit_code == 0 end) do
          {_output, 0} ->
            {:ok, "Redis service started"}

          _ ->
            last_output = results |> List.wrap() |> List.last() |> elem(0)
            {:error, "Failed to start Redis: #{String.trim(last_output)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error ->
      {:error, "Failed to start Redis: #{Exception.message(error)}"}
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
