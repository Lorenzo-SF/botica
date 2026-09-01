defmodule Botica.Dashboard do
  @moduledoc """
  Minimal HTTP dashboard for botica check results.

  Serves a tiny plain-HTML page (no external deps) with the last state
  of every check, plus a Prometheus `/metrics` endpoint reusing
  `Botica.Report`.

  The dashboard is a zero-dependency `:gen_tcp` listener so it works in
  any OTP release without adding a web framework.

  ## Usage

  The dashboard is **not** started by default (botica is a library, not
  a service). Start it explicitly:

      Botica.Dashboard.start_link(port: 8080, provider: fn -> results end)

  The `:provider` fun returns the list of check results to display; it
  defaults to the last scheduler history or an empty list.

  ## Routes

    * `GET /` — HTML status page
    * `GET /health` — `200 OK` / `503` with `ok|degraded|fail` body
    * `GET /metrics` — Prometheus text format via `Botica.Report`
  """

  use GenServer

  alias Botica.Report

  @default_port 8080

  @type result_provider :: (-> [map()])

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the dashboard HTTP server.

  ## Options

    * `:port` — listen port (default 8080)
    * `:provider` — zero-arity fun returning `[result_map]` (default: empty)
    * `:interface` — bind address (default `{127, 0, 0, 1}`)
    * `:name` — registered name (default `__MODULE__`; pass a unique name
      to run several dashboards in the same VM, e.g. in tests)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Stops the dashboard.

  Pass `:name` when the dashboard was started with a custom name.
  """
  @spec stop(atom() | pid()) :: :ok
  def stop(name \\ __MODULE__) do
    GenServer.stop(name, :normal, 5_000)
  end

  @doc """
  Current listen port (useful in tests to learn the ephemeral port).
  """
  @spec port(atom() | pid()) :: :inet.port_number()
  def port(name \\ __MODULE__) do
    GenServer.call(name, :port)
  end

  # ---------------------------------------------------------------------------
  # GenServer
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, @default_port)
    provider = Keyword.get(opts, :provider, fn -> [] end)
    interface = Keyword.get(opts, :interface, {127, 0, 0, 1})

    case :gen_tcp.listen(port, [:binary, packet: :raw, active: false, reuseaddr: true, ip: interface]) do
      {:ok, listen_socket} ->
        {:ok, {actual_port, _}} = :inet.sockname(listen_socket)

        # Accept loop in a separate process so the dashboard GenServer
        # stays responsive to control messages.
        acceptor = spawn_link(fn -> accept_loop(listen_socket, provider) end)

        {:ok, %{port: actual_port, acceptor: acceptor, listen_socket: listen_socket}}

      {:error, reason} ->
        {:stop, {:listen_failed, reason}}
    end
  end

  @impl true
  def handle_call(:port, _from, state) do
    {:reply, state.port, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # HTTP handling
  # ---------------------------------------------------------------------------

  defp accept_loop(listen_socket, provider) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        # Handle each connection in its own process so a slow client
        # cannot stall the accept loop.
        _ = spawn(fn -> serve(socket, provider) end)
        accept_loop(listen_socket, provider)

      {:error, _reason} ->
        # Listen socket closed (server stopping) — exit normally.
        :ok
    end
  end

  defp serve(socket, provider) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, request} ->
        {method, path} = parse_request(request)
        response = route(method, path, provider)
        :gen_tcp.send(socket, response)
        :gen_tcp.close(socket)

      {:error, _reason} ->
        :gen_tcp.close(socket)
    end
  end

  defp parse_request(request) do
    [request_line | _] = String.split(request, "\r\n")
    [method, path | _] = String.split(request_line, " ")
    {method, path}
  end

  defp route("GET", "/", provider) do
    html_response(provider.())
  end

  defp route("GET", "/health", provider) do
    results = provider.()
    summary = Report.summary(results)
    status = Report.health_status(summary)

    body =
      case status do
        :ok -> "ok"
        :degraded -> "degraded"
        :fail -> "fail"
      end

    code = if status == :fail, do: 503, else: 200
    text_response(code, body)
  end

  defp route("GET", "/metrics", provider) do
    text_response(200, Report.prometheus_text(provider.()), "text/plain; version=0.0.4")
  end

  defp route(_method, _path, _provider) do
    text_response(404, "not found")
  end

  defp html_response(results) do
    summary = Report.summary(results)

    rows =
      results
      |> Enum.map(fn result ->
        ~s(<tr><td>#{escape_html(to_string(result.id))}</td>) <>
          ~s(<td>#{escape_html(result.status)}</td>) <>
          ~s(<td>#{escape_html(result.message || "")}</td></tr>)
      end)
      |> Enum.join("\n")

    body = """
    <!DOCTYPE html>
    <html><head><title>Botica Dashboard</title></head><body>
    <h1>Botica</h1>
    <p>total: #{summary.total} · ok: #{summary.ok} · warning: #{summary.warning} · error: #{summary.error}</p>
    <table border="1"><tr><th>check</th><th>status</th><th>message</th></tr>
    #{rows}
    </table>
    </body></html>
    """

    text_response(200, body, "text/html")
  end

  defp text_response(code, body, content_type \\ "text/plain; charset=utf-8") do
    status_line =
      case code do
        200 -> "200 OK"
        404 -> "404 Not Found"
        503 -> "503 Service Unavailable"
        _ -> "#{code} Status"
      end

    "HTTP/1.1 #{status_line}\r\n" <>
      "Content-Type: #{content_type}\r\n" <>
      "Content-Length: #{byte_size(body)}\r\n" <>
      "Connection: close\r\n\r\n" <>
      body
  end

  defp escape_html(nil), do: ""

  defp escape_html(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp escape_html(other), do: escape_html(to_string(other))
end
