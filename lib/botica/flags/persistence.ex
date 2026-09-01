defmodule Botica.Flags.Persistence do
  @moduledoc """
  Behaviour for persisting feature flags outside of the ETS cache.

  The `Botica.Flags.Store` GenServer uses the configured persistence
  adapter as the source of truth at boot (`load_all/0`) and writes
  through on every mutation (`save_flag/1`, `delete_flag/1`). The ETS
  table remains the in-memory read cache: O(1) reads without a
  GenServer round-trip.

  ## Built-in adapters

    * `Botica.Flags.Persistence.Disk` — atomic JSON file (default,
      `~/.botica/flags.json`)

  ## Custom adapters

      defmodule MyApp.FlagPersistence do
        @behaviour Botica.Flags.Persistence

        @impl true
        def load_all, do: {:ok, []}

        @impl true
        def save_flag(_flag), do: :ok

        @impl true
        def delete_flag(_name), do: :ok
      end

  Configure the active adapter in `:botica` application env:

      config :botica, :flags_persistence, [
        adapter: MyApp.FlagPersistence,
        opts: []
      ]
  """

  alias Botica.Flags.Flag

  @doc """
  Loads every persisted flag. Called once at Store boot to populate the
  ETS cache. Returns `{:ok, [Flag.t()]}` or `{:error, term()}`.
  """
  @callback load_all() :: {:ok, [Flag.t()]} | {:error, term()}

  @doc """
  Persists a single flag. Called on every Store mutation.
  """
  @callback save_flag(Flag.t()) :: :ok | {:error, term()}

  @doc """
  Removes a flag from the persistent store.
  """
  @callback delete_flag(atom()) :: :ok | {:error, term()}

  @doc """
  Returns the configured persistence adapter from application env.
  Defaults to `Botica.Flags.Persistence.Disk` with no options.

  ## Configuration

      config :botica, :flags_persistence, [
        adapter: Botica.Flags.Persistence.Disk,
        opts: [path: "/var/lib/botica/flags.json"]
      ]
  """
  @spec configured() :: {module(), keyword()}
  def configured do
    case Application.get_env(:botica, :flags_persistence, []) do
      [] ->
        {Botica.Flags.Persistence.Disk, []}

      opts when is_list(opts) ->
        {Keyword.get(opts, :adapter, Botica.Flags.Persistence.Disk),
         Keyword.get(opts, :opts, [])}

      other ->
        raise ArgumentError,
              "[Botica.Flags.Persistence] invalid :flags_persistence config: #{inspect(other)}"
    end
  end

  @doc """
  Disables persistence entirely (`adapter: false`). The Store then behaves
  as a pure in-memory registry — useful for tests and ephemeral processes.

      config :botica, :flags_persistence, adapter: false
  """
  @spec enabled?() :: boolean()
  def enabled? do
    adapter = Keyword.get(Application.get_env(:botica, :flags_persistence, []), :adapter)

    adapter not in [false, nil]
  end
end
