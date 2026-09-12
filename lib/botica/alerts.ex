defmodule Botica.Alerts do
  @moduledoc """
  Alert hooks for repeated check failures and recovery.

  The alert tracker keeps a consecutive-failure counter per check id.
  When a check fails `threshold` times in a row (default 3), the
  subscriber is notified with `notify(:failed, result)`; when the check
  recovers (returns ok after having failed), the subscriber is notified
  with `notify(:recovered, result)`.

  ## Subscribers

  A subscriber is any module implementing the `Botica.Alerts.Subscriber`
  behaviour (or a plain `fun.(kind, result)`).

  ## Example

      defmodule MyApp.Slack do
        @behaviour Botica.Alerts.Subscriber

        @impl true
        def notify(:failed, result) do
          # POST to Slack
          :ok
        end

        def notify(:recovered, result), do: :ok
      end

      Botica.Alerts.subscribe(MyApp.Slack)
      Botica.Alerts.track(check_id, result)   # call after every run

  ## Behaviour

      defmodule Botica.Alerts.Subscriber do
        @callback notify(kind :: :failed | :recovered, result :: map()) :: :ok | {:error, term()}
      end
  """

  use GenServer

  @table :botica_alerts_state
  @default_threshold 3

  @doc false
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Registers a subscriber (module implementing the behaviour or a
  `fun.(kind, result)`).
  """
  @spec subscribe(module() | (atom() -> term() | (atom(), map() -> term()))) :: :ok
  def subscribe(subscriber) do
    GenServer.call(__MODULE__, {:subscribe, subscriber})
  end

  @doc """
  Removes a subscriber.
  """
  @spec unsubscribe(module() | fun()) :: :ok
  def unsubscribe(subscriber) do
    GenServer.call(__MODULE__, {:unsubscribe, subscriber})
  end

  @doc """
  Updates the consecutive-failure counter for a check and fires alerts.

  Call this after every check run with the check result:

      Botica.Alerts.track(result.id, result)

  A check that fails `threshold` consecutive times triggers
  `notify(:failed, result)`. The first ok after a failure streak
  triggers `notify(:recovered, result)`.

  Returns `:ok` always (alerts are fire-and-forget).
  """
  @spec track(atom(), map()) :: :ok
  def track(check_id, result) when is_atom(check_id) and is_map(result) do
    GenServer.call(__MODULE__, {:track, check_id, result}, 5_000)
  end

  @doc """
  Returns the current consecutive failure count for a check.
  """
  @spec failures(atom()) :: non_neg_integer()
  def failures(check_id) when is_atom(check_id) do
    case :ets.lookup(@table, check_id) do
      [{^check_id, count}] -> count
      [] -> 0
    end
  end

  @doc """
  Formats an alert line with a severity-specific prefix.

  ## Severity levels

    * `:info` — blue `[i]` prefix
    * `:warning` — yellow `[!]` prefix
    * `:error` — red `[x]` prefix
    * `:critical` — red `[X]` prefix (with double border)

  ## Examples

      iex> Botica.Alerts.format_alert(:warning, "Postgres latency > 1s")
      "[!] Postgres latency > 1s"

      iex> Botica.Alerts.format_alert(:critical, "Disk full")
      "[X] Disk full"
  """
  @spec format_alert(atom(), String.t()) :: String.t()
  def format_alert(severity, message) when is_atom(severity) and is_binary(message) do
    prefix =
      case severity do
        :info -> "[i]"
        :warning -> "[!]"
        :error -> "[x]"
        :critical -> "[X]"
        _ -> "[?]"
      end

    "#{prefix} #{message}"
  end

  @doc """
  Resets the failure counter for a check (e.g. after manual intervention).
  """
  @spec reset(atom()) :: :ok
  def reset(check_id) when is_atom(check_id) do
    GenServer.call(__MODULE__, {:reset, check_id})
  end

  @doc """
  Subscriber behaviour.
  """
  defmodule Subscriber do
    @moduledoc """
    Behaviour for alert subscribers. See `Botica.Alerts`.

    `notify/2` receives the kind (`:failed` | `:recovered`) and the check
    result map. It must return `:ok` or `{:error, reason}`.
    """
    @callback notify(:failed | :recovered, map()) :: :ok | {:error, term()}
  end

  # ---------------------------------------------------------------------------
  # GenServer
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    # The table is shared across all tracker instances (named, public).
    # Only create it once — a second tracker (e.g. custom threshold in
    # tests) must reuse the existing table.
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
    end

    {:ok, %{subscribers: [], threshold: Keyword.get(opts, :threshold, @default_threshold)}}
  end

  @impl true
  def handle_call({:subscribe, subscriber}, _from, state) do
    if subscriber in state.subscribers do
      {:reply, :ok, state}
    else
      {:reply, :ok, %{state | subscribers: [subscriber | state.subscribers]}}
    end
  end

  def handle_call({:unsubscribe, subscriber}, _from, state) do
    {:reply, :ok, %{state | subscribers: List.delete(state.subscribers, subscriber)}}
  end

  def handle_call({:reset, check_id}, _from, state) do
    :ets.delete(@table, check_id)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:track, check_id, result}, _from, state) do
    failed = result.status == :error

    count =
      case :ets.lookup(@table, check_id) do
        [{^check_id, prev}] -> prev
        [] -> 0
      end

    if failed do
      new_count = count + 1
      :ets.insert(@table, {check_id, new_count})

      if count < state.threshold and new_count >= state.threshold do
        notify_all(:failed, result, state.subscribers)
      end
    else
      if count > 0 do
        :ets.insert(@table, {check_id, 0})
        notify_all(:recovered, result, state.subscribers)
      end
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Internal
  # ---------------------------------------------------------------------------

  defp notify_all(kind, result, subscribers) do
    Enum.each(subscribers, fn subscriber ->
      _ = Task.start(fn -> notify_one(subscriber, kind, result) end)
    end)
  end

  defp notify_one(subscriber, kind, result) when is_function(subscriber, 2) do
    subscriber.(kind, result)
  end

  defp notify_one(subscriber, kind, result) when is_atom(subscriber) do
    if function_exported?(subscriber, :notify, 2) do
      subscriber.notify(kind, result)
    else
      require Logger
      Logger.warning("[Botica.Alerts] subscriber #{inspect(subscriber)} missing notify/2")
    end
  end
end
