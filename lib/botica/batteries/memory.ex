defmodule Botica.Batteries.Memory do
  alias Apero.OS
  alias Trebejo.Util

  @moduledoc """
  Predefined health check for system memory usage.

  This module provides a check that monitors memory consumption
  and warns when it exceeds safe thresholds.

  Uses `Apero.OS.type/0` to dispatch directly between Linux (`free`)
  and macOS (`vm_stat`) instead of a blind fallback. All command
  execution is routed through `Trebejo.Util.run_cmd_legacy/3` with
  arg lists for consistent timeout handling and structured errors.

  ## Usage

      config = %{
        app_name: "myapp",
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
  Checks system memory usage. Dispatches Linux vs macOS via `Apero.OS.type/0`.
  """
  @spec check_memory(non_neg_integer(), non_neg_integer()) :: Botica.Types.check_result()
  def check_memory(warning_threshold, error_threshold) do
    case OS.type() do
      :linux -> check_linux_memory(warning_threshold, error_threshold)
      :macos -> check_macos_memory(warning_threshold, error_threshold)
      :windows -> {:error, "Windows memory check not implemented"}
      _ -> {:error, "Unsupported OS: #{OS.type()}"}
    end
  end

  # ── Private ────────────────────────────────────────────────────────────────

  defp check_linux_memory(warning_threshold, error_threshold) do
    case Util.run_cmd_legacy("cat", ["/proc/meminfo"], timeout: 5_000) do
      {output, 0} ->
        parse_linux_memory(output, warning_threshold, error_threshold)

      {output, code} ->
        {:error, "/proc/meminfo read failed (exit #{code}): #{String.trim(output)}"}
    end
  end

  defp check_macos_memory(warning_threshold, error_threshold) do
    case Util.run_cmd_legacy("vm_stat", [], timeout: 5_000) do
      {output, 0} ->
        parse_macos_memory(output, warning_threshold, error_threshold)

      {output, code} ->
        {:error, "vm_stat exited #{code}: #{String.trim(output)}"}
    end
  end

  # ── Linux parsing (/proc/meminfo via cat) ─────────────────────────────────

  defp parse_linux_memory(output, warning_threshold, error_threshold) do
    lines = String.split(output, "\n", trim: true)

    mem_total_line = find_mem_line(lines, "MemTotal:")
    mem_available_line = find_mem_line(lines, "MemAvailable:")

    with {mem_total, :valid} <- parse_mem_value_with_validation(mem_total_line),
         {mem_available, :valid} <- parse_mem_value_with_validation(mem_available_line) do
      used_percent = round((mem_total - mem_available) / mem_total * 100)
      classify_usage(used_percent, warning_threshold, error_threshold)
    else
      _ -> {:error, "Could not parse /proc/meminfo output"}
    end
  end

  defp find_mem_line(lines, prefix) do
    Enum.find(lines, fn line -> String.starts_with?(line, prefix) end)
  end

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

  # ── macOS parsing (vm_stat pages) ──────────────────────────────────────────

  defp parse_macos_memory(output, warning_threshold, error_threshold) do
    lines = String.split(output, "\n", trim: true)

    {active, inactive, wired, free} = parse_macos_pages(lines)
    total = active + inactive + wired + free
    used = active + wired

    used_percent = if total > 0, do: round(used / total * 100), else: 0

    classify_usage(used_percent, warning_threshold, error_threshold)
  rescue
    _ -> {:error, "Could not parse macOS vm_stat output"}
  end

  defp parse_macos_pages(lines) do
    {
      find_and_parse_page(lines, "Pages active:"),
      find_and_parse_page(lines, "Pages inactive:"),
      find_and_parse_page(lines, "Pages wired:"),
      find_and_parse_page(lines, "Pages free:")
    }
  end

  defp find_and_parse_page(lines, prefix) do
    case Enum.find(lines, fn l -> String.starts_with?(l, prefix) end) do
      nil -> 0

      line ->
        line
        |> String.replace(prefix, "")
        |> String.trim()
        |> String.replace_trailing(".", "")
        |> String.to_integer()
    end
  end

  # ── Shared classification ──────────────────────────────────────────────────

  defp classify_usage(used_percent, warning_threshold, error_threshold) do
    cond do
      used_percent >= error_threshold ->
        {:error, "Memory usage critically high: #{used_percent}% used"}

      used_percent >= warning_threshold ->
        {:warning, "Memory usage elevated: #{used_percent}% used"}

      true ->
        {:ok, "Memory usage normal: #{used_percent}% used"}
    end
  end
end
