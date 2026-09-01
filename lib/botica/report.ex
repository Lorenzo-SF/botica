defmodule Botica.Report do
  @moduledoc """
  Exports check results to observability backends.

  Two exporters are provided:

    * `prometheus_text/1` — renders results in the Prometheus text
      exposition format (`application/openmetrics`-compatible subset),
      ready for a Prometheus / VictoriaMetrics scrape endpoint.
    * `otel_export/1` — emits OTel-style metrics via `:telemetry`
      events, so any OTel collector handler attached to
      `[:botica, :report, :otel]` receives them.

  ## Examples

      results = [
        %{id: :database, name: "Database", status: :ok, message: "up", fix_command: nil},
        %{id: :memory, name: "Memory", status: :warning, message: "low", fix_command: nil}
      ]

      iex> Botica.Report.prometheus_text(results)
      "# HELP botica_check_status ..."

      iex> Botica.Report.otel_export(results)
      :ok
  """

  alias Botica.Check.Result

  @metric_name "botica_check_status"

  @doc """
  Renders results in Prometheus text exposition format.

  Each check produces a gauge line:

      # HELP botica_check_status Current status of botica health checks
      # TYPE botica_check_status gauge
      botica_check_status{check="database",status="ok"} 1

  The check `id` and `status` are emitted as labels; the value is always
  `1` (the status is encoded in the label). Label values are escaped per
  the Prometheus spec (backslash, double-quote, newline).
  """
  @spec prometheus_text([Result.t() | map()]) :: binary()
  def prometheus_text(results) when is_list(results) do
    [
      "# HELP #{@metric_name} Current status of botica health checks",
      "# TYPE #{@metric_name} gauge",
      Enum.map(results, fn result -> metric_line(result) end)
    ]
    |> List.flatten()
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  @doc """
  Emits OTel-style metrics for every result via `:telemetry`.

  Each check emits:

      :telemetry.execute(
        [:botica, :report, :otel],
        %{value: 1},
        %{check: id, status: "ok", name: name}
      )

  Attach a handler on that event in your OTel exporter to forward the
  metrics. Returns `:ok` unconditionally (telemetry never blocks).
  """
  @spec otel_export([Result.t() | map()]) :: :ok
  def otel_export(results) when is_list(results) do
    Enum.each(results, fn result ->
      :telemetry.execute(
        [:botica, :report, :otel],
        %{value: 1},
        %{check: result.id, status: Atom.to_string(result.status), name: result.name}
      )
    end)

    :ok
  end

  @doc """
  Aggregates results into a summary (delegates to `Botica.Check.Result`).
  """
  @spec summary([Result.t() | map()]) :: map()
  def summary(results), do: Result.summarize(results)

  @doc """
  Overall health status from a summary: `:ok` | `:degraded` | `:fail`.
  """
  @spec health_status(map()) :: :ok | :degraded | :fail
  def health_status(summary), do: Result.health_status(summary)

  # ---------------------------------------------------------------------------
  # Internal
  # ---------------------------------------------------------------------------

  defp metric_line(%{id: id, status: status}) do
    check_label = escape_label(to_string(id))
    status_label = escape_label(Atom.to_string(status))

    ~s(#{@metric_name}{check="#{check_label}",status="#{status_label}"} 1)
  end

  # Prometheus label escaping: backslash, double-quote, newline.
  defp escape_label(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end
end
