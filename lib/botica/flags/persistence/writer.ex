defmodule Botica.Flags.Persistence.Writer do
  @moduledoc """
  Serializes persistence writes to the configured adapter.

  The `Botica.Flags.Store` GenServer delegates every mutation to this
  writer via `cast`, so disk writes happen strictly one at a time in
  mailbox order. This avoids read-modify-write races between concurrent
  flag mutations (two writes reading the same file and one overwriting
  the other).

  The writer is deliberately NOT linked to the Store: a slow disk must
  never crash the flags registry. Errors are logged, not raised.

  ## Supervision

  Started by `Botica.Application` after the Store. If the Store is
  restarted, the writer keeps its queue — writes are idempotent against
  the adapter.
  """

  use GenServer

  alias Botica.Flags.Persistence

  @doc false
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Enqueues a flag save. Returns `:ok` immediately; the write happens
  asynchronously in mailbox order.
  """
  @spec save(Botica.Flags.Flag.t()) :: :ok
  def save(%Botica.Flags.Flag{} = flag) do
    GenServer.cast(__MODULE__, {:save, flag})
  end

  @doc """
  Enqueues a flag deletion. Returns `:ok` immediately.
  """
  @spec delete(atom()) :: :ok
  def delete(name) when is_atom(name) do
    GenServer.cast(__MODULE__, {:delete, name})
  end

  @doc """
  Number of pending writes in the mailbox queue (diagnostics).
  """
  @spec pending() :: non_neg_integer()
  def pending do
    GenServer.call(__MODULE__, :pending, 5_000)
  end

  @impl true
  def init(_opts) do
    {:ok, %{pending: 0}}
  end

  @impl true
  def handle_cast({:save, flag}, state) do
    case do_write(:save_flag, flag) do
      :ok -> :ok
      {:error, reason} -> log_error(:save_flag, flag, reason)
    end

    {:noreply, %{state | pending: state.pending + 1}}
  end

  def handle_cast({:delete, name}, state) when is_atom(name) do
    case do_write(:delete_flag, name) do
      :ok -> :ok
      {:error, reason} -> log_error(:delete_flag, name, reason)
    end

    {:noreply, %{state | pending: state.pending + 1}}
  end

  @impl true
  def handle_call(:pending, _from, state) do
    {:reply, state.pending, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Internal
  # ---------------------------------------------------------------------------

  # Resolve the adapter at write time so tests that swap config between
  # cases take effect without restarting the writer.
  defp do_write(fun, arg) do
    {adapter, _opts} = Persistence.configured()
    apply(adapter, fun, [arg])
  end

  defp log_error(fun, arg, reason) do
    require Logger

    Logger.error(
      "[Botica.Flags] persistence #{fun} failed for #{inspect(arg)}: #{inspect(reason)}"
    )
  end
end
