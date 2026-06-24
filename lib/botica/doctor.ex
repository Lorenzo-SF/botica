defmodule Botica.Doctor do
  @moduledoc """
  Environment diagnostics and auto-repair — returns structured results.

  Define checks and use `run/1` to diagnose or `fix/1` to repair.
  All functions return data structures — the caller decides how to display.

  ## Check definition

      config = %{
        app_name: "myapp",
        checks: [
          %{
            id: :postgresql,
            name: "PostgreSQL",
            description: "Database server",
            priority: 1,
            check: fn -> {:ok, "v14"} end,
            fix: fn -> {:ok, "installed"} end,
            fix_command: "sudo apt install postgresql-14"
          }
        ]
      }

  Each `check/0` returns `{:ok, msg}`, `{:warning, msg}` or `{:error, msg}`.
  Each `fix/0` returns `{:ok, msg}`, `{:error, msg}` or `:skipped`.

  ## Return values

  `run/1` returns `{:ok, results}` — all checks always return ok wrapper,
  the individual status is embedded in each result map.

  `fix/1` returns `{:ok, fix_report}` — a detailed report of what was applied.

  `summary/1` returns a map with counts and a `passed?` boolean.

  ## Timeout support

  Checks can specify a timeout in milliseconds:

      %{
        id: :slow_check,
        name: "Slow Check",
        timeout: 5000,  # 5 second timeout
        check: fn -> ... end
      }

  The default timeout is 30 seconds. Global timeout can be overridden in `run/2`.
  """

  alias Botica.Batteries.{Disk, Memory, PostgreSQL, Redis}
  alias Botica.Check.Result
  alias Botica.Flags
  alias Botica.Repair.Fixer
  alias Botica.Runner.Executor
  alias Botica.Runner.Sequencer
  alias Botica.Types

  @type check_id :: Types.check_id()
  @type check_result :: Types.check_result()
  @type fix_result :: Types.fix_result()
  @type check_def :: Types.check_def()
  @type result :: Types.result()
  @type summary :: Types.summary()
  @type fix_report :: Types.fix_report()
  @type config :: Types.config()

  @doc """
  Runs all checks in parallel and returns structured results.

  ## Options

  - `:timeout` - Global timeout per check in ms (default: 30_000)
  - `:stop_on_first_error` - Stop after first error (default: false)
  - `:continue_on_error` - Continue after errors (default: true)

  ## Examples

      iex> config = %{
      ...>   app_name: \"myapp\",
      ...>   checks: [
      ...>     %{
      ...>       id: :check1,
      ...>       name: \"Check 1\",
      ...>       description: \"A check\",
      ...>       priority: 1,
      ...>       check: fn -> {:ok, \"ok\"} end,
      ...>       fix: fn -> :skipped end,
      ...>       fix_command: nil
      ...>     }
      ...>   ]
      ...> }
      iex> {:ok, [result]} = Botica.Doctor.run(config)
      iex> result.status
      :ok
  """
  @spec run(config()) :: {:ok, [result()]} | {:error, String.t()}
  def run(config) do
    run(config, [])
  end

  @doc """
  Runs all checks in parallel with custom options.

  ## Options

  - `:timeout` - Global timeout per check in ms (default: 30_000)
  - `:stop_on_first_error` - Stop after first error (default: false)
  - `:continue_on_error` - Continue after errors (default: true)
  """
  @spec run(config(), Types.executor_options()) :: {:ok, [result()]} | {:error, String.t()}
  def run(config, opts) when is_list(opts) do
    case validate_config(config) do
      :ok ->
        Executor.execute(config, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Runs fixes for all checks with errors and returns a detailed report.

  ## Examples

      iex> config = %{
      ...>   app_name: \"myapp\",
      ...>   checks: [
      ...>     %{
      ...>       id: :failing,
      ...>       name: \"Failing\",
      ...>       description: \"A failing check\",
      ...>       priority: 1,
      ...>       check: fn -> {:error, \"something wrong\"} end,
      ...>       fix: fn -> {:ok, \"fixed!\"} end,
      ...>       fix_command: \"some command\"
      ...>     }
      ...>   ]
      ...> }
      iex> {:ok, report} = Botica.Doctor.fix(config)
      iex> report.applied
      [:failing]
  """
  @spec fix(config()) :: {:ok, fix_report()} | {:error, String.t()}
  def fix(config) do
    case validate_config(config) do
      :ok ->
        case run(config) do
          {:ok, results} ->
            Fixer.fix(config, results)

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Summarizes a list of check results into a single map.

  ## Examples

      iex> results = [
      ...>   %{status: :ok},
      ...>   %{status: :ok},
      ...>   %{status: :warning},
      ...>   %{status: :error}
      ...> ]
      iex> Botica.Doctor.summary(results)
      %{ok: 2, warning: 1, error: 1, total: 4, passed?: false}
  """
  @spec summary([result()]) :: summary()
  def summary(results) do
    Result.summarize(results)
  end

  @doc """
  Runs a quick health check and returns a simple pass/fail map.

  Shorthand for `run/1` + `summary/1` — returns `%{status: :ok | :degraded | :fail, summary: summary()}`.

  ## Examples

      iex> config = %{
      ...>   app_name: \"myapp\",
      ...>   checks: [
      ...>     %{
      ...>       id: :check1,
      ...>       name: \"Check 1\",
      ...>       description: \"A check\",
      ...>       priority: 1,
      ...>       check: fn -> {:ok, \"ok\"} end,
      ...>       fix: fn -> :skipped end,
      ...>       fix_command: nil
      ...>     }
      ...>   ]
      ...> }
      iex> result = Botica.Doctor.health_check(config)
      iex> result.status
      :ok
      iex> result.summary.passed?
      true
  """
  @spec health_check(config()) ::
          %{status: :ok | :degraded | :fail, summary: summary()}
          | %{status: :fail, summary: summary(), error: String.t()}
  def health_check(config) do
    case run(config) do
      {:ok, results} ->
        summary = summary(results)

        status =
          case Result.health_status(summary) do
            :ok -> :ok
            :degraded -> :degraded
            :fail -> :fail
          end

        %{status: status, summary: summary}

      {:error, reason} ->
        %{
          status: :fail,
          summary: %{ok: 0, warning: 0, error: 1, total: 0, passed?: false},
          error: reason
        }
    end
  end

  @doc """
  Validates the configuration and returns `:ok` or `{:error, reason}`.

  ## Examples

      iex> Botica.Doctor.validate(%{app_name: \"test\", checks: []})
      :ok
      iex> Botica.Doctor.validate(%{app_name: \"test\"})
      {:error, "config.checks must be a list"}
      iex> Botica.Doctor.validate(%{checks: []})
      {:error, "config.app_name must be a string"}
  """
  @spec validate(config()) :: :ok | {:error, String.t()}
  def validate(config), do: validate_config(config)

  @doc """
  Returns available battery checks (predefined health checks).

  ## Examples

      iex> batteries = Botica.Doctor.batteries()
      iex> is_list(batteries)
      true
  """
  @spec batteries() :: [check_def()]
  def batteries do
    [
      PostgreSQL.check_def([]),
      Redis.check_def([]),
      Memory.check_def([]),
      Disk.check_def([])
    ]
  end

  @doc """
  Sorts checks by priority (lower values run first).

  ## Examples

      iex> checks = [
      ...>   %{id: :b, priority: 2},
      ...>   %{id: :a, priority: 1}
      ...> ]
      iex> Botica.Doctor.sort_checks(checks)
      [%{id: :a, priority: 1}, %{id: :b, priority: 2}]
  """
  @spec sort_checks([check_def()]) :: [check_def()]
  def sort_checks(checks) do
    Sequencer.sort(checks)
  end

  # ---------------------------------------------------------------------------
  # Flags diagnostic — extends the Doctor with a feature-flags section
  # ---------------------------------------------------------------------------

  @doc """
  Returns a diagnostic snapshot of the current `Botica.Flags` registry.

  Shape:

      %{
        count: 3,
        flags: [
          %{name: :beta_search, status: :enabled, default: true, rollout: nil},
          %{name: :new_dashboard, status: :disabled, default: false, rollout: nil},
          %{name: :rate_limiting, status: :rollout, default: false, rollout: 25}
        ]
      }

  Intended to be printed by CLI / REPL wrappers as part of the botica
  diagnostic banner. Safe to call when no flags are defined — returns an
  empty list under `:flags`.
  """
  @spec flags_summary() :: %{
          required(:count) => non_neg_integer(),
          required(:flags) => [map()]
        }
  def flags_summary do
    summary =
      Flags.all()
      |> Enum.map(fn flag ->
        status =
          cond do
            flag.enabled and is_integer(flag.rollout) -> :rollout
            flag.enabled -> :enabled
            true -> :disabled
          end

        %{
          name: flag.name,
          status: status,
          default: flag.default,
          rollout: flag.rollout,
          description: flag.description
        }
      end)

    %{count: length(summary), flags: summary}
  end

  @doc """
  Formats the `flags_summary/0` output as a human-readable string suitable
  for the `delfos doctor`-style banners.

  Returns an empty string when no flags are defined.

  ## Example output

      Flags (3 defined):
        ✓ beta_search     enabled  (default: true)
        ✗ new_dashboard   disabled (default: false)
        ~ rate_limiting   rollout 25% (default: false)
  """
  @spec format_flags_summary() :: String.t()
  def format_flags_summary do
    case flags_summary() do
      %{count: 0} ->
        ""

      %{count: count, flags: flags} ->
        rows =
          Enum.map_join(flags, "\n", fn flag ->
            icon = icon_for(flag.status)
            state = state_for(flag.status, flag.rollout)
            default = "(default: #{flag.default})"
            "  #{icon} #{pad(flag.name)}  #{pad(state)}  #{default}"
          end)

        "Flags (#{count} defined):\n#{rows}"
    end
  end

  defp icon_for(:enabled), do: "✓"
  defp icon_for(:disabled), do: "✗"
  defp icon_for(:rollout), do: "~"

  defp state_for(:rollout, pct) when is_integer(pct), do: "rollout #{pct}%"
  defp state_for(:enabled, _), do: "enabled"
  defp state_for(:disabled, _), do: "disabled"

  defp pad(name) when is_atom(name), do: name |> Atom.to_string() |> String.pad_trailing(16)
  defp pad(name) when is_binary(name), do: String.pad_trailing(name, 16)
  defp pad(name), do: name |> to_string() |> String.pad_trailing(16)

  # Private functions

  defp validate_config(config) do
    cond do
      not is_map(config) ->
        {:error, "config must be a map"}

      not Map.has_key?(config, :app_name) ->
        {:error, "config.app_name must be a string"}

      not is_binary(config.app_name) ->
        {:error, "config.app_name must be a string"}

      not Map.has_key?(config, :checks) ->
        {:error, "config.checks must be a list"}

      not is_list(config.checks) ->
        {:error, "config.checks must be a list"}

      true ->
        :ok
    end
  end
end
