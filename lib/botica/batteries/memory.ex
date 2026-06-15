defmodule Botica.Batteries.Memory do
  @moduledoc """
  Predefined health check for system memory usage.

  This module provides a check that monitors memory consumption
  and warns when it exceeds safe thresholds.

  ## Usage

      config = %{
        app_name: \"myapp\",
        checks: [
          Botica.Batteries.Memory.check(warning_threshold: 80, error_threshold: 95)
        ]
      }

  ## Options

  - `:warning_threshold` - Memory % to trigger warning (default: 80)
  - `:error_threshold` - Memory % to trigger error (default: 95)
  - `:timeout` - Check timeout in ms (default: 5000)
  """

  @behaviour Botica.Check.Behaviour

  @impl true
  def check_def(opts \\ []) do
    warning_threshold = Keyword.get(opts, :warning_threshold, 80)
    error_threshold = Keyword.get(opts, :error_threshold, 95)
    timeout = Keyword.get(opts, :timeout, 5000)

    %{
      id: :memory,
      name: "Memory",
      description: "System memory usage is within safe limits",
      priority: 5,
      tags: [:system],
      timeout: timeout,
      check: fn -> check_memory(warning_threshold, error_threshold) end,
      fix: fn -> :skipped end,
      fix_command: nil
    }
  end

  @doc """
  Checks system memory usage on macOS or Linux.
  """
  @spec check_memory(non_neg_integer(), non_neg_integer()) :: Botica.Types.check_result()
  def check_memory(warning_threshold, error_threshold) do
    case System.cmd("free", [], stderr_to_stdout: true) do
      {output, 0} when is_binary(output) ->
        parse_linux_memory(output, warning_threshold, error_threshold)

      _ ->
        # Try macOS
        case System.cmd("vm_stat", [], stderr_to_stdout: true) do
          {output, 0} when is_binary(output) ->
            parse_macos_memory(output, warning_threshold, error_threshold)

          _ ->
            {:error, "Could not determine memory usage"}
        end
    end
  rescue
    error ->
      {:error, "Failed to check memory: #{Exception.message(error)}"}
  end

  # Parse Linux /proc/meminfo
  defp parse_linux_memory(output, warning_threshold, error_threshold) do
    lines = String.split(output, "\n", trim: true)

    mem_total_line = find_mem_line(lines, "MemTotal:")
    mem_available_line = find_mem_line(lines, "MemAvailable:")

    with {mem_total, :valid} <- parse_mem_value_with_validation(mem_total_line),
         {mem_available, :valid} <- parse_mem_value_with_validation(mem_available_line),
         {used_percent, _} <- {round((mem_total - mem_available) / mem_total * 100), true} do
      cond do
        used_percent >= error_threshold ->
          {:error, "Memory usage critically high: #{used_percent}% used"}

        used_percent >= warning_threshold ->
          {:warning, "Memory usage elevated: #{used_percent}% used"}

        true ->
          {:ok, "Memory usage normal: #{used_percent}% used"}
      end
    else
      _ ->
        {:error, "Could not parse memory info"}
    end
  end

  defp find_mem_line(lines, prefix) do
    Enum.find(lines, fn line -> String.starts_with?(line, prefix) end)
  end

  # Returns {value, :valid} or {0, :invalid} for validation
  defp parse_mem_value_with_validation(nil), do: {0, :invalid}
  defp parse_mem_value_with_validation(""), do: {0, :invalid}

  defp parse_mem_value_with_validation(line) do
    value =
      line
      |> String.split(~r/\s+/, trim: true)
      |> Enum.at(1, "0")
      |> String.to_integer()

    {value, :valid}
  end

  # Parse macOS vm_stat output
  defp parse_macos_memory(output, warning_threshold, error_threshold) do
    # vm_stat output needs to be parsed differently
    # Pages active, inactive, wired, free
    # page size is typically 4096 bytes (can be different on some Macs)
    # Note: page_size calculation kept for future use if needed
    _page_size = get_page_size()

    lines = String.split(output, "\n", trim: true)

    {active, inactive, wired, free} = parse_macos_pages(lines)

    total = active + inactive + wired + free
    # active + wired pages are "in use"
    used = active + wired

    used_percent = if total > 0, do: round(used / total * 100), else: 0

    cond do
      used_percent >= error_threshold ->
        {:error, "Memory usage critically high: #{used_percent}% used"}

      used_percent >= warning_threshold ->
        {:warning, "Memory usage elevated: #{used_percent}% used"}

      true ->
        {:ok, "Memory usage normal: #{used_percent}% used"}
    end
  rescue
    _ ->
      {:error, "Could not parse macOS memory info"}
  end

  defp parse_macos_pages(lines) do
    active = find_and_parse_page(lines, "Pages active:")
    inactive = find_and_parse_page(lines, "Pages inactive:")
    wired = find_and_parse_page(lines, "Pages wired:")
    free = find_and_parse_page(lines, "Pages free:")

    {active, inactive, wired, free}
  end

  defp find_and_parse_page(lines, prefix) do
    case Enum.find(lines, fn l -> String.starts_with?(l, prefix) end) do
      nil ->
        0

      line ->
        line
        |> String.replace(prefix, "")
        |> String.trim()
        |> String.replace_trailing(".", "")
        |> String.to_integer()
    end
  end

  defp get_page_size do
    case System.cmd("pagesize", [], stderr_to_stdout: true) do
      {size, 0} -> String.trim(size) |> String.to_integer()
      # default
      _ -> 4096
    end
  end
end
