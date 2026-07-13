defmodule Botica.Batteries.Redis do
  alias Arrea.Command
  alias Trebejo.Network
  alias Trebejo.Util

  @moduledoc """
  Predefined health check for Redis cache server.

  This module provides a ready-to-use check that verifies Redis
  is accessible. It prefers the `redis-cli` binary and falls back
  to a raw TCP port check (via `Trebejo.Network.port_open?/3`) when
  the binary is not installed.

  All command execution uses arg lists — never interpolated into
  shell strings — to prevent shell injection. Routed through
  `Trebejo.Util.run_cmd_legacy/3` for consistent timeout handling
  and structured errors.

  ## Usage

      config = %{
        app_name: "myapp",
        checks: [
          Botica.Batteries.Redis.check()
        ]
      }

  ## Options

  - `:host` - Redis host (default: "localhost")
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

  Uses `redis-cli` when available. Falls back to a TCP probe on
  the configured port via `Trebejo.Network.port_open?/3` when the
  binary is not installed.
  """
  @spec check_connection(String.t(), non_neg_integer()) :: Botica.Types.check_result()
  def check_connection(host, port) do
    cond do
      Command.command_exists?("redis-cli") ->
        check_via_redis_cli(host, port)

      Network.port_open?(host, port, timeout: 2_000) ->
        {:ok, "Redis port #{port} is open at #{host} (redis-cli not installed)"}

      true ->
        {:error, "Redis unreachable at #{host}:#{port} (no redis-cli, port closed)"}
    end
  end

  @doc """
  Attempts to start the Redis service.

  Tries `systemctl start redis-server` first, falls back to
  `systemctl start redis` for distros that name the unit differently.
  """
  @spec start_service() :: Botica.Types.fix_result()
  def start_service do
    with :ok <- check_sudo_available(),
         {:ok, _} <- try_start_commands() do
      {:ok, "Redis service started"}
    else
      {:error, _} = err -> err
    end
  end

  # ── Private helpers ───────────────────────────────────────────────────────

  defp check_via_redis_cli(host, port) do
    case Util.run_cmd_legacy("redis-cli", ["-h", host, "-p", to_string(port), "ping"],
           timeout: 5_000
         ) do
      {"PONG\r\n" <> _, 0} ->
        {:ok, "Redis is responding at #{host}:#{port}"}

      {"PONG\n" <> _, 0} ->
        {:ok, "Redis is responding at #{host}:#{port}"}

      {output, 0} ->
        if String.trim(output) == "PONG" do
          {:ok, "Redis is responding at #{host}:#{port}"}
        else
          {:error, "Redis unexpected output: #{String.trim(output)}"}
        end

      {output, code} ->
        {:error, "Redis not responding (exit #{code}): #{String.trim(output)}"}
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

  defp try_start_commands do
    units = ["redis-server", "redis"]
    results = Enum.map(units, &try_start_unit/1)

    case Enum.find(results, fn r -> match?({:ok, _}, r) end) do
      {:ok, _} = ok -> ok
      nil -> {:error, format_start_failures(results)}
    end
  end

  defp try_start_unit(unit) do
    case Util.run_cmd_legacy("sudo", ["systemctl", "start", unit], timeout: 30_000) do
      {_, 0} ->
        {:ok, "Redis service started (unit: #{unit})"}

      {output, code} ->
        {:error, {:unit, unit, code, String.trim(output)}}
    end
  end

  defp format_start_failures(results) do
    details =
      Enum.map_join(results, "\n", fn
        {:error, {:unit, unit, code, msg}} -> "  #{unit}: exit #{inspect(code)} — #{msg}"
        other -> "  #{inspect(other)}"
      end)

    "Failed to start Redis (tried all unit names):\n#{details}"
  end
end
