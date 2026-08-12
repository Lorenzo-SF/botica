defmodule Botica.Flags.Store do
  @moduledoc """
  ETS-backed storage for `Botica.Flags.Flag` structs.

  ## Architecture

    - The ETS table `:botica_flags` is **`:public`** and
      `read_concurrency: true` so reads are O(1) and lock-free, even
      under heavy concurrent load. The `:public` choice is deliberate:
      it lets callers read directly without bouncing through the
      GenServer, which is the whole point of having an ETS backend.
      Mutations still go through the GenServer (`put/1`, `delete/1`)
      so the table stays consistent.
    - The GenServer is also where flag lifecycle events (defined,
      enabled, disabled, rollout-changed) are emitted via telemetry.

  ## Usage

  In most cases you should not call this module directly — use the
  `Botica.Flags` facade instead. Direct access is allowed when you need
  the cheapest possible read and you're certain the Store is up:

      iex> Botica.Flags.Store.get(:my_flag)
      {:ok, %Botica.Flags.Flag{...}}

      iex> Botica.Flags.Store.all()
      [%Botica.Flags.Flag{...}, ...]
  """

  use GenServer

  alias Botica.Flags.{Config, Flag, Persistence}

  @table :botica_flags
  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the `Botica.Flags.Store` GenServer. Called automatically by
  `Botica.Application`. Use `start_link/1` from custom supervision
  trees when you need to override the default application config.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the underlying ETS table name. Useful in tests for clearing the
  registry between cases: `Store.table() |> :ets.delete_all_objects()`.
  """
  @spec table() :: :ets.tab()
  def table, do: @table

  @doc """
  Direct ETS read — no GenServer round-trip. Returns `{:ok, flag}` or `:error`.
  """
  @spec get(atom()) :: {:ok, Botica.Flags.Flag.t()} | :error
  def get(name) when is_atom(name) do
    case :ets.lookup(@table, name) do
      [{^name, flag}] -> {:ok, flag}
      [] -> :error
    end
  end

  @doc """
  Direct ETS read of all flags. Returns a list (may be empty), sorted
  by `updated_at` descending so most recently touched flags appear first.
  """
  @spec all() :: [Botica.Flags.Flag.t()]
  def all do
    @table
    |> :ets.tab2list()
    |> Enum.map(fn {_name, flag} -> flag end)
    |> Enum.sort(fn a, b -> DateTime.compare(a.updated_at, b.updated_at) != :lt end)
  end

  @doc """
  GenServer-mediated write. Serialised to avoid race conditions between
  concurrent definitions / enable / disable / set calls. 5s timeout
  is generous for an in-memory ETS write and surfaces a stalled server
  fast.
  """
  @spec put(Botica.Flags.Flag.t()) :: :ok
  def put(%Botica.Flags.Flag{} = flag) do
    GenServer.call(__MODULE__, {:put, flag}, 5_000)
  end

  @doc """
  Remove a flag from the registry. 5s timeout — see `put/1` for rationale.
  """
  @spec delete(atom()) :: :ok
  def delete(name) when is_atom(name) do
    GenServer.call(__MODULE__, {:delete, name}, 5_000)
  end

  @doc """
  Total number of registered flags. Cheap ETS count.
  """
  @spec count() :: non_neg_integer()
  def count do
    :ets.info(@table, :size) || 0
  end

  @doc """
  Diagnostic snapshot: total writes since the GenServer started
  plus the current ETS size. Useful for `mix botica:config` and
  for debugging flag registration.
  """
  @spec stats() :: %{writes: non_neg_integer(), count: non_neg_integer()}
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # ---------------------------------------------------------------------------
  # GenServer
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    # Create the ETS table with fast concurrent reads.
    :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])

    # Load persisted flags first (source of truth), then apply defaults
    # from application config only for flags that are not persisted.
    load_persisted()

    if :ets.info(@table, :size) == 0 do
      Config.get()
      |> Enum.each(fn flag -> :ets.insert(@table, {flag.name, flag}) end)
    end

    {:ok, %{writes: 0}}
  end

  @impl true
  def handle_call({:put, %Botica.Flags.Flag{} = flag}, _from, state) do
    # Preserve created_at if flag already exists (TOCTOU fix).
    # Also always refresh updated_at atomically in the GenServer.
    created_at =
      case :ets.lookup(@table, flag.name) do
        [{_name, existing}] -> existing.created_at
        [] -> flag.created_at
      end

    now =
      :erlang.system_time(:microsecond)
      |> DateTime.from_unix!(:microsecond)

    fresh = %{flag | created_at: created_at, updated_at: now}

    :ets.insert(@table, {fresh.name, fresh})

    # Persist outside the GenServer mailbox so a slow disk never blocks
    # flag mutations. The Writer serializes writes in mailbox order so
    # concurrent mutations cannot race on the JSON file. Persistence
    # failures are logged, not raised: the in-memory registry stays
    # authoritative for the current run.
    if Persistence.enabled?() do
      Persistence.Writer.save(fresh)
    end

    # Fire-and-forget telemetry: a slow listener must never block the
    # GenServer mailbox. Tasks are intentionally not linked (`:noproc`
    # from a long-dead VM would crash the GenServer otherwise).
    _ =
      Task.start(fn ->
        :telemetry.execute([:botica, :flags, :put], %{value: fresh}, %{})
      end)

    {:reply, :ok, %{state | writes: state.writes + 1}}
  end

  @impl true
  def handle_call({:delete, name}, _from, state) when is_atom(name) do
    :ets.delete(@table, name)

    # Persist the removal — see `:put` handler for rationale.
    if Persistence.enabled?() do
      Persistence.Writer.delete(name)
    end

    # Fire-and-forget telemetry — see `:put` handler for rationale.
    _ =
      Task.start(fn ->
        :telemetry.execute([:botica, :flags, :delete], %{name: name}, %{})
      end)

    {:reply, :ok, %{state | writes: state.writes + 1}}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, %{writes: state.writes, count: count()}, state}
  end

  # Catch-all for unexpected messages — ignore them silently.
  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Persistence helpers
  # ---------------------------------------------------------------------------

  # Boot-time load: populate the ETS cache from the configured adapter.
  # Failures are logged; defaults from config still apply.
  defp load_persisted do
    if Persistence.enabled?() do
      {adapter, _opts} = Persistence.configured()

      case adapter.load_all() do
        {:ok, flags} when is_list(flags) ->
          Enum.each(flags, fn %Flag{} = flag -> :ets.insert(@table, {flag.name, flag}) end)

        {:error, reason} ->
          require Logger
          Logger.warning("[Botica.Flags] persistence load failed: #{inspect(reason)}")

        other ->
          require Logger
          Logger.warning("[Botica.Flags] unexpected persistence load result: #{inspect(other)}")
      end
    end
  end
end
