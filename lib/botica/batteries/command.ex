defmodule Botica.Batteries.Command do
  @moduledoc """
  Shared command runner for the batteries.

  Every battery (`Disk`, `Memory`, `PostgreSQL`, `Redis`) shells out
  to an external tool — `df`, `cat /proc/meminfo`, `pg_isready`,
  `redis-cli`, `sudo systemctl`. They used to do that through
  `Trebejo.Util.run_cmd_legacy/3`, but `trebejo` is deliberately
  *not* in `deps` (botica must resolve and build without it), so
  the `Code.ensure_loaded?` guard was always false and every
  battery returned the placeholder `{"trebejo not loaded", 127}`.
  The checks degraded to noise instead of actually reporting
  anything.

  This module keeps the Trebejo path for anyone who does have it
  loaded, and falls back to `System.cmd/3` otherwise, so a battery
  always produces a real answer. The return shape matches
  Trebejo's: `{output_string, exit_code}`.

  ## Options

    * `:timeout` — milliseconds, default `5_000`
    * `:env` — environment map, default `%{}`
    * `:cd` — working directory, default `"."`
    * `:stderr_to_stdout` — default `false`

  """

  @default_timeout 5_000

  @doc """
  Runs `cmd` with `args`, preferring `Trebejo.Util.run_cmd_legacy/3`
  when that module is loaded and exporting the function, and falling
  back to `System.cmd/3` otherwise.

  Returns `{output, exit_code}` where `output` is an empty string
  when the binary could not be spawned at all (`:enoent`) and
  `exit_code` is `127`, matching the shell convention for
  "command not found".
  """
  @spec run(String.t(), [String.t()], keyword()) :: {String.t(), integer()}
  def run(cmd, args, opts \\ []) when is_binary(cmd) and is_list(args) do
    if trebejo_available?() do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(Trebejo.Util, :run_cmd_legacy, [cmd, args, opts])
    else
      system_cmd(cmd, args, opts)
    end
  end

  defp trebejo_available? do
    Code.ensure_loaded?(Trebejo.Util) and function_exported?(Trebejo.Util, :run_cmd_legacy, 3)
  end

  defp system_cmd(cmd, args, opts) do
    system_opts =
      [
        stderr_to_stdout: Keyword.get(opts, :stderr_to_stdout, false),
        cd: Keyword.get(opts, :cd, ".")
      ]
      |> put_env(Keyword.get(opts, :env))

    timeout = Keyword.get(opts, :timeout, @default_timeout)

    # `System.cmd/3` has no `:timeout` option, and these batteries
    # shell out to things like `sudo systemctl` that can block on a
    # password prompt indefinitely. Wrap it in a task and give up on
    # the deadline instead of hanging the health check.
    task =
      Task.async(fn ->
        System.cmd(cmd, args, system_opts)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {output, exit_code}} -> {output, exit_code}
      {:exit, reason} -> {"", classify_exit(reason)}
      nil -> {"", 124}
    end
  rescue
    # `System.cmd` raises when the binary is not on PATH. The shell
    # convention for that is 127, and the batteries already expect
    # a non-zero code they can classify, so mirror it instead of
    # letting the exception escape into a health check.
    ErlangError -> {"", 127}
  end

  defp classify_exit(:timeout), do: 124
  defp classify_exit(:noproc), do: 127
  defp classify_exit(_), do: 1

  defp put_env(system_opts, env) when map_size(env) == 0, do: system_opts

  defp put_env(system_opts, env) when is_map(env) or is_list(env),
    do: Keyword.put(system_opts, :env, env)

  defp put_env(system_opts, _env), do: system_opts
end
