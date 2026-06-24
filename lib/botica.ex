defmodule Botica do
  @moduledoc """
  Botica provides environment diagnostics, health checks, and feature flags.

  ## Modules

    * `Botica.Doctor` — run health checks, summarise, fix failures
    * `Botica.Flags` — feature flags with ETS backend and per-entity rollouts
    * `Botica.Flags.Store` — GenServer that owns the ETS table
    * `Botica.Flags.Flag` — struct for a single flag
    * `Botica.Runner.*`, `Botica.Check.*`, `Botica.Batteries.*` — internal pieces

  ## Feature flags quick start

      Botica.Flags.define(:new_dashboard, default: false)
      Botica.Flags.define(:beta_search, default: true)
      Botica.Flags.define(:rate_limiting, default: false, rollout: 25)

      Botica.Flags.enabled?(:new_dashboard)               # false
      Botica.Flags.enabled?(:rate_limiting, for: user)    # deterministic per user
      Botica.Flags.enable(:new_dashboard)

  See `Botica.Flags` for full API.

  ## Diagnostics quick start

  Define a config with checks and use the Doctor module to run diagnostics:

      config = %{
        app_name: "myapp",
        checks: [
          %{
            id: :postgresql,
            name: "PostgreSQL",
            description: "Database is accessible",
            priority: 1,
            check: fn -> {:ok, "connected"} end,
            fix: fn -> {:ok, "restarted"} end,
            fix_command: "sudo systemctl start postgresql"
          }
        ]
      }

      # Run health checks
      {:ok, results} = Botica.run(config)

      # Run fixes for failed checks
      {:ok, report} = Botica.fix(config)

      # Quick health check
      result = Botica.health_check(config)

      # Snapshot of feature flags
      summary = Botica.Doctor.flags_summary()
      banner = Botica.Doctor.format_flags_summary()

  ## Predefined Checks (Batteries)

  Botica includes predefined checks for common services:

      config = %{
        app_name: "myapp",
        checks: [
          Botica.Batteries.PostgreSQL.check(),
          Botica.Batteries.Redis.check(),
          Botica.Batteries.Memory.check(),
          Botica.Batteries.Disk.check()
        ]
      }

  ## API

  - `Botica.run/1` - Run all checks, returns `{:ok, [result]}`
  - `Botica.run/2` - Run checks with options (timeout, stop_on_first_error)
  - `Botica.fix/1` - Run fixes for failed checks, returns `{:ok, fix_report}`
  - `Botica.health_check/1` - Convenience wrapper returning pass/fail status
  - `Botica.batteries/0` - List available predefined checks
  - `Botica.Flags.*` - Feature flag API
  - `Botica.Doctor` - Full module with detailed functions
  """

  @doc """
  Runs all health checks in parallel and returns structured results.

  See `Botica.Doctor.run/1` for full documentation.
  """
  defdelegate run(config), to: Botica.Doctor, as: :run

  @doc """
  Runs all health checks in parallel with custom options.

  See `Botica.Doctor.run/2` for available options.
  """
  defdelegate run(config, opts), to: Botica.Doctor, as: :run

  @doc """
  Runs fixes for all checks that returned an error.

  Returns a detailed report of what was applied, failed, or skipped.

  See `Botica.Doctor.fix/1` for full documentation.
  """
  defdelegate fix(config), to: Botica.Doctor, as: :fix

  @doc """
  Runs a quick health check and returns a simple status map.

  See `Botica.Doctor.health_check/1` for full documentation.
  """
  defdelegate health_check(config), to: Botica.Doctor, as: :health_check

  @doc """
  Returns a list of available predefined checks (batteries).

  See `Botica.Doctor.batteries/0` for full documentation.
  """
  defdelegate batteries, to: Botica.Doctor, as: :batteries

  @doc """
  Validates a configuration map.

  See `Botica.Doctor.validate/1` for full documentation.
  """
  defdelegate validate(config), to: Botica.Doctor, as: :validate

  # ---------------------------------------------------------------------------
  # Feature flags — see `Botica.Flags` for full documentation.
  # ---------------------------------------------------------------------------

  defdelegate define(name, opts \\ []), to: Botica.Flags
  defdelegate enable(name), to: Botica.Flags
  defdelegate disable(name), to: Botica.Flags
  defdelegate set(name, opts), to: Botica.Flags
  defdelegate delete(name), to: Botica.Flags
  defdelegate enabled?(name), to: Botica.Flags
  defdelegate enabled?(name, opts), to: Botica.Flags
  defdelegate get(name), to: Botica.Flags
  defdelegate all(), to: Botica.Flags
  defdelegate count(), to: Botica.Flags
end
