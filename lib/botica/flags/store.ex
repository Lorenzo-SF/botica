defmodule Botica.Flags.Store do
  @moduledoc """
  ETS-backed storage for `Botica.Flags.Flag` structs.

  ## Architecture

    - The ETS table `:botica_flags` is `:public` and `read_concurrency: true`
      so reads are O(1) and lock-free, even under heavy concurrent load.
    - Writes go through the GenServer (`put/1`, `delete/1`) so that mutations
      are serialised and the table stays consistent.
    - The GenServer is also where flag lifecycle events (defined, enabled,
      disabled, rollout-changed) can be hooked in the future via telemetry.

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

  @table :botica_flags

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

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
  concurrent definitions / enable / disable / set calls.
  """
  @spec put(Botica.Flags.Flag.t()) :: :ok
  def put(%Botica.Flags.Flag{} = flag) do
    GenServer.call(__MODULE__, {:put, flag})
  end

  @doc """
  Remove a flag from the registry.
  """
  @spec delete(atom()) :: :ok
  def delete(name) when is_atom(name) do
    GenServer.call(__MODULE__, {:delete, name})
  end

  @doc """
  Total number of registered flags. Cheap ETS count.
  """
  @spec count() :: non_neg_integer()
  def count do
    :ets.info(@table, :size) || 0
  end

  # ---------------------------------------------------------------------------
  # GenServer
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    # :set + :public + :named_table + read_concurrency is the canonical
    # "fast concurrent reads, serialised writes" combo.
    :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
    {:ok, %{writes: 0}}
  end

  @impl true
  def handle_call({:put, %Botica.Flags.Flag{} = flag}, _from, state) do
    # Refresh updated_at on every write so introspection sees when the flag
    # last changed state. Use :erlang.system_time(:microsecond) so back-to-back
    # writes within the same second still get distinct timestamps (DateTime.utc_now/0
    # truncated to :second collides on fast systems).
    fresh = %{
      flag
      | updated_at:
          (:erlang.system_time(:microsecond)
           |> DateTime.from_unix!(:microsecond))
    }
    :ets.insert(@table, {fresh.name, fresh})
    {:reply, :ok, %{state | writes: state.writes + 1}}
  end

  @impl true
  def handle_call({:delete, name}, _from, state) when is_atom(name) do
    :ets.delete(@table, name)
    {:reply, :ok, %{state | writes: state.writes + 1}}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, %{writes: state.writes, count: count()}, state}
  end
end
