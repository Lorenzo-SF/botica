defmodule Botica.Batteries.Disk do
  @moduledoc """
  Predefined health check for disk space usage.

  This module provides a check that monitors disk consumption
  and warns when available space falls below safe thresholds.

  ## Usage

      config = %{
        app_name: \"myapp\",
        checks: [
          Botica.Batteries.Disk.check(path: "/", warning_threshold: 80, error_threshold: 95)
        ]
      }

  ## Options

  - `:path` - Path to check (default: \"/\")
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
    case System.cmd("df", ["-k", path], stderr_to_stdout: true) do
      {output, 0} when is_binary(output) ->
        parse_df_output(output, warning_threshold, error_threshold)

      _ ->
        {:error, "Could not determine disk usage for #{path}"}
    end
  rescue
    error ->
      {:error, "Failed to check disk: #{Exception.message(error)}"}
  end

  defp parse_df_output(output, warning_threshold, error_threshold) do
    lines = String.split(output, "\n", trim: true)

    # Find the line with the actual usage (skip header)
    data_line =
      Enum.find(lines, fn line ->
        not String.contains?(line, "Filesystem") and String.contains?(line, "%")
      end) || ""

    cond do
      data_line == "" ->
        {:error, "Could not parse disk usage output"}

      true ->
        # Last column before % is the use percentage
        case parse_use_percentage(data_line) do
          nil ->
            {:error, "Could not determine disk usage percentage"}

          used_percent ->
            cond do
              used_percent >= error_threshold ->
                {:error, "Disk space critically low: #{used_percent}% used"}

              used_percent >= warning_threshold ->
                {:warning, "Disk space running low: #{used_percent}% used"}

              true ->
                {:ok, "Disk space normal: #{used_percent}% used"}
            end
        end
    end
  end

  defp parse_use_percentage(line) do
    # Pattern: "Filesystem  Size  Used Avail Use% Mounted on"
    # or on macOS: "Filesystem  512-blocks  Used  Available  Capacity  iused  ifree  %iused  Mounted on"
    # We need to find the Use% column
    parts = String.split(String.trim(line), ~r/\s+/, trim: true)

    case parts do
      # Linux format: ... Use%
      parts when length(parts) >= 5 ->
        use_index = length(parts) - 2

        Enum.at(parts, use_index)
        |> String.replace("%", "")
        |> String.trim()
        |> String.to_integer()
        |> then(fn val -> if val in 0..100, do: val, else: nil end)

      _ ->
        nil
    end
  end
end
