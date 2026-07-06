defmodule Botica.Batteries.Redis do
  alias Apero.Network
  alias Arrea.Command

  @moduledoc """
  Predefined health check for Redis cache server.

  This module provides a ready-to-use check that verifies Redis
  is accessible. It prefers the `redis-cli` binary and falls back
  to a raw TCP port check (via `Apero.Network.port_open?/3`) when
  the binary is not installed.

  All command execution is routed through `Command.execute/2` so
  consumers get the full Arrea infra for free: real timeout
  cancellation, validation, telemetry, shell handling, and the
  sudo allowlist configured in `config/config.exs`.

  ## Installation

  Optional: install `redis-cli` (ships with the `redis-tools` /
  `redis-server` packages on most distros). Without it, the battery
  degrades to a raw TCP probe on the configured port.

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
  the configured port via `Apero.Network.port_open?/3` when the
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
  Requires sudo NOPASSWD configured for those systemctl calls
  (see `config :arrea, :engine, sudo_allowlist` in `config/config.exs`).
  """
  @spec start_service() :: Botica.Types.fix_result()
  def start_service do
    with :ok <- check_sudo_available(),
         :ok <- try_start_commands() do
      {:ok, "Redis service started"}
    else
      {:error, _} = err -> err
    end
  end

  # ── Private helpers ───────────────────────────────────────────────────────

  defp check_via_redis_cli(host, port) do
    cmd = "redis-cli -h #{host} -p #{port} ping"

    case Command.execute(cmd, timeout: 5_000, validate: false) do
      {:ok, %{exit_code: 0, stdout: "PONG\r\n" <> _}} ->
        {:ok, "Redis is responding at #{host}:#{port}"}

      {:ok, %{exit_code: 0, stdout: "PONG\n" <> _}} ->
        {:ok, "Redis is responding at #{host}:#{port}"}

      {:ok, %{exit_code: 0, stdout: stdout}} ->
        # redis-cli on success sometimes prints "PONG" without trailing newline
        if String.trim(stdout) == "PONG" do
          {:ok, "Redis is responding at #{host}:#{port}"}
        else
          {:error, "Redis unexpected output: #{String.trim(stdout)}"}
        end

      {:ok, %{exit_code: code, stdout: output}} ->
        {:error, "Redis not responding (exit #{code}): #{String.trim(output)}"}

      {:error, :timeout} ->
        {:error, "Redis check timed out at #{host}:#{port}"}

      {:error, reason} ->
        {:error, "Redis check failed: #{inspect(reason)}"}
    end
  end

  defp check_sudo_available do
    if Command.command_exists?("sudo") do
      case Command.execute("sudo -n true", validate: false) do
        {:ok, %{exit_code: 0}} ->
          :ok

        _ ->
          {:error, "sudo requires a password or is not available. Configure NOPASSWD in sudoers."}
      end
    else
      {:error, "sudo not found in PATH"}
    end
  end

  # Try multiple systemctl unit names because different distros name
  # the redis service differently (redis-server on Debian/Ubuntu,
  # redis on RHEL/Fedora/Arch).
  defp try_start_commands do
    units = ["redis-server", "redis"]
    results = Enum.map(units, &try_start_unit/1)

    case Enum.find(results, fn r -> match?({:ok, _}, r) end) do
      {:ok, _} = ok -> ok
      nil -> {:error, format_start_failures(results)}
    end
  end

  defp try_start_unit(unit) do
    case Command.execute("sudo systemctl start #{unit}", timeout: 30_000) do
      {:ok, %{exit_code: 0}} ->
        {:ok, "Redis service started (unit: #{unit})"}

      {:ok, %{exit_code: code, stdout: output}} ->
        {:error, {:unit, unit, code, String.trim(output)}}

      {:error, reason} ->
        {:error, {:unit, unit, nil, inspect(reason)}}
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
