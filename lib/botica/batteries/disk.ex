defmodule Botica.Batteries.Disk do
  alias Trebejo.Util

  @moduledoc """
  Predefined health check for disk space usage.

  This module provides a check that monitors disk consumption
  and warns when available space falls below safe thresholds.

  Uses `Trebejo.Util.run_cmd_legacy/3` with arg lists — never
  interpolated into shell strings — to prevent shell injection.
  The `LC_ALL=C` env var ensures locale-stable output.

  ## Usage

      config = %{
        app_name: "myapp",
        checks: [
          Botica.Batteries.Disk.check(path: "/", warning_threshold: 80, error_threshold: 95)
        ]
      }

  ## Options

  - `:path` - Path to check (default: "/")
  - `:warning_threshold` - Disk % to trigger warning (default: 80)
  - `:error_threshold` - Disk % to trigger error (default: 95)
  - `:timeout` - Check timeout in ms (default: 5000)
  """

  @behaviour Botica.Check.Behaviour

  @impl true
  def check_def(opts \\ []) do
    path = Keyword.get(opts, :path, "/")
    warning_threshold = Keyword.get(opts, :warning_threshold, 80)
    error_threshold = Keyword.get(opts, :error_threshold, 95)
    timeout = Keyword.get(opts, :timeout, 5000)

    %{
      id: :disk,
      name: "Disk",
      description: "Disk space is available",
      priority: 4,
      tags: [:system],
      timeout: timeout,
      check: fn -> check_disk(path, warning_threshold, error_threshold) end,
      fix: fn -> :skipped end,
      fix_command: nil
    }
  end

  @doc """
  Checks disk space usage for a given path.
  """
  @spec check_disk(String.t(), non_neg_integer(), non_neg_integer()) ::
          Botica.Types.check_result()
  def check_disk(path, warning_threshold, error_threshold) do
    # Force POSIX locale so the parser can rely on English column
    # headers (Filesystem, Use%, etc.).
    env = %{"LC_ALL" => "C"}

    case Util.run_cmd_legacy("df", ["-k", path], timeout: 5_000, env: env) do
      {output, 0} ->
        parse_df_output(output, warning_threshold, error_threshold)

      {output, code} ->
        {:error, "df exited #{code} for #{path}: #{String.trim(output)}"}
    end
  end

  defp parse_df_output(output, warning_threshold, error_threshold) do
    lines = String.split(output, "\n", trim: true)

    data_line =
      Enum.find(lines, fn line ->
        not String.contains?(line, "Filesystem") and String.contains?(line, "%")
      end) || ""

    if data_line == "" do
      {:error, "Could not parse disk usage output"}
    else
      case parse_use_percentage(data_line) do
        nil -> {:error, "Could not determine disk usage percentage"}
        used_percent -> classify_usage(used_percent, warning_threshold, error_threshold)
      end
    end
  end

  defp classify_usage(used_percent, warning_threshold, error_threshold) do
    cond do
      used_percent >= error_threshold ->
        {:error, "Disk space critically low: #{used_percent}% used"}

      used_percent >= warning_threshold ->
        {:warning, "Disk space running low: #{used_percent}% used"}

      true ->
        {:ok, "Disk space normal: #{used_percent}% used"}
    end
  end

  defp parse_use_percentage(line) do
    parts = String.split(String.trim(line), ~r/\s+/, trim: true)

    case parts do
      parts when length(parts) >= 5 ->
        use_index = length(parts) - 2

        parts
        |> Enum.at(use_index)
        |> String.replace("%", "")
        |> String.trim()
        |> String.to_integer()
        |> validate_percentage()

      _ ->
        nil
    end
  end

  defp validate_percentage(val) when val in 0..100, do: val
  defp validate_percentage(_), do: nil
end
