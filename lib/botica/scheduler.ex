defmodule Botica.Scheduler do
  @moduledoc """
  Runs check groups on a schedule.

  A scheduler entry pairs a schedule with a `Botica.Check.Group` (or any
  zero-arity runner function). The scheduler fires the group, stores the
  result in a bounded ETS history, and optionally notifies a subscriber
  after every run.

  ## Schedules

  Two forms are supported:

    * `every: {:minutes, N}` / `{:seconds, N}` / `{:milliseconds, N}` —
      fixed interval.
    * `cron: "*/5 * * * *"` — a 5-field cron expression (minute hour
      day-of-month month day-of-week). Only `*` and `*/N` steps are
      supported in the first field; other fields must be `*`.

  ## Example

      group = Botica.Check.Group.new(:db, [check_db], timeout_ms: 2_000)

      :ok = Botica.Scheduler.add(:db_every_5m, group, every: {:minutes, 5})
      :ok = Botica.Scheduler.add(:db_at_night, group, cron: "*/5 * * * *")

  ## History

  The last `max_history` results per schedule are kept in a private ETS
  table (default 10). Query with `history/1`.
  """

  use GenServer

  alias Botica.Check.Group

  @table :botica_scheduler_history
  @max_history_default 10

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc false
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a scheduled run.

  ## Options

    - `:every` — `{:milliseconds, n}` | `{:seconds, n}` | `{:minutes, n}`
    - `:cron` — cron expression (5 fields, `*`/`*/N` in minute field)
    - `:runner` — zero-arity fun (defaults to `fn -> Group.run(group) end`)
    - `:max_history` — history entries kept (default 10)
    - `:notify` — `fun.({:ok, results}) | ({:error, reason})` after each run

  Exactly one of `:every` / `:cron` must be provided.
  """
  @spec add(atom(), Group.t() | (-> term()), keyword()) :: :ok | {:error, term()}
  def add(name, group_or_fun, opts \\ []) do
    GenServer.call(__MODULE__, {:add, name, group_or_fun, opts}, 5_000)
  end

  @doc """
  Removes a scheduled run.
  """
  @spec remove(atom()) :: :ok
  def remove(name) when is_atom(name) do
    GenServer.call(__MODULE__, {:remove, name}, 5_000)
  end

  @doc """
  Returns the last `max_history` results for a schedule (most recent first).
  """
  @spec history(atom()) :: [term()]
  def history(name) when is_atom(name) do
    :ets.lookup(@table, name)
    |> case do
      [{^name, results}] -> results
      [] -> []
    end
  end

  @doc """
  Returns all registered schedules (name → schedule spec).
  """
  @spec all() :: [{atom(), term()}]
  def all do
    GenServer.call(__MODULE__, :all, 5_000)
  end

  @doc """
  Manually triggers a schedule now (useful for tests and on-demand runs).
  """
  @spec run_now(atom()) :: :ok | {:error, :not_found}
  def run_now(name) when is_atom(name) do
    GenServer.call(__MODULE__, {:run_now, name}, 5_000)
  end

  # ---------------------------------------------------------------------------
  # GenServer
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
    {:ok, %{schedules: %{}}}
  end

  @impl true
  def handle_call({:add, name, group_or_fun, opts}, _from, state) do
    with {:ok, schedule} <- parse_schedule(opts),
         {:ok, interval_ms} <- safe_interval_ms(schedule),
         {:ok, runner} <- build_runner(group_or_fun, opts) do
      max_history = Keyword.get(opts, :max_history, @max_history_default)
      notify = Keyword.get(opts, :notify)
      timer_ref = Process.send_after(self(), {:tick, name}, interval_ms)

      entry = %{
        schedule: schedule,
        runner: runner,
        interval_ms: interval_ms,
        max_history: max_history,
        notify: notify,
        timer_ref: timer_ref
      }

      {:reply, :ok, put_in(state.schedules[name], entry)}
    else
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  def handle_call({:remove, name}, _from, state) do
    case Map.pop(state.schedules, name) do
      {nil, _schedules} ->
        {:reply, :ok, state}

      {entry, schedules} ->
        Process.cancel_timer(entry.timer_ref)
        :ets.delete(@table, name)
        {:reply, :ok, %{state | schedules: schedules}}
    end
  end

  def handle_call(:all, _from, state) do
    schedules =
      state.schedules
      |> Enum.map(fn {name, entry} -> {name, entry.schedule} end)

    {:reply, schedules, state}
  end

  def handle_call({:run_now, name}, _from, state) do
    case Map.fetch(state.schedules, name) do
      {:ok, entry} ->
        run_entry(name, entry)
        {:reply, :ok, state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_info({:tick, name}, state) do
    case Map.fetch(state.schedules, name) do
      {:ok, entry} ->
        # Reschedule before running: long groups must not drift ticks.
        timer_ref = Process.send_after(self(), {:tick, name}, entry.interval_ms)
        updated = %{entry | timer_ref: timer_ref}
        new_state = put_in(state.schedules[name], updated)

        run_entry(name, entry)
        {:noreply, new_state}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Internal
  # ---------------------------------------------------------------------------

  defp run_entry(name, entry) do
    result =
      try do
        {:ok, entry.runner.()}
      rescue
        error -> {:error, {:runner_crashed, Exception.message(error)}}
      catch
        kind, reason -> {:error, {kind, reason}}
      end

    append_history(name, result, entry.max_history)
    if entry.notify, do: entry.notify.(result)
  end

  defp append_history(name, result, max_history) do
    results =
      case :ets.lookup(@table, name) do
        [{^name, prev}] -> [result | prev] |> Enum.take(max_history)
        [] -> [result]
      end

    :ets.insert(@table, {name, results})
  end

  # -- schedule parsing ------------------------------------------------------

  defp parse_schedule(opts) do
    cond do
      Keyword.has_key?(opts, :every) ->
        {:ok, {:every, Keyword.fetch!(opts, :every)}}

      Keyword.has_key?(opts, :cron) ->
        parse_cron(Keyword.fetch!(opts, :cron))

      true ->
        {:error, :missing_schedule}
    end
  end

  defp parse_cron(expr) when is_binary(expr) do
    case String.split(expr, " ", trim: true) do
      [minute, "*", "*", "*", "*"] ->
        case parse_step(minute) do
          {:ok, step} when step >= 1 and step <= 59 -> {:ok, {:cron, step}}
          _ -> {:error, {:invalid_cron, expr}}
        end

      _ ->
        {:error, {:invalid_cron, expr}}
    end
  end

  defp parse_cron(_other), do: {:error, :invalid_cron}

  # Accepts `*` (step 1) or `*/N`.
  defp parse_step("*"), do: {:ok, 1}
  defp parse_step("*/" <> n), do: parse_step(n)
  defp parse_step(n) when is_binary(n), do: parse_int(n)
  defp parse_step(_), do: {:error, :invalid_step}

  defp parse_int(n) do
    case Integer.parse(n) do
      {int, ""} -> {:ok, int}
      _ -> {:error, :invalid_int}
    end
  end

  defp interval_ms({:every, {:milliseconds, ms}}) when is_integer(ms) and ms > 0, do: ms
  defp interval_ms({:every, {:seconds, s}}) when is_integer(s) and s > 0, do: s * 1_000

  defp interval_ms({:every, {:minutes, m}}) when is_integer(m) and m > 0,
    do: m * 60_000

  defp interval_ms({:cron, step}), do: step * 60_000

  defp interval_ms(_other), do: raise(ArgumentError, "[Botica.Scheduler] invalid interval")

  # interval_ms/1 raises on malformed intervals; wrap it so `add/3` can
  # return {:error, :invalid_interval} instead of crashing the GenServer.
  defp safe_interval_ms(schedule) do
    {:ok, interval_ms(schedule)}
  rescue
    ArgumentError -> {:error, :invalid_interval}
  end

  # -- runner building -------------------------------------------------------

  defp build_runner(%Group{} = group, _opts) do
    {:ok, fn -> Group.run(group) end}
  end

  defp build_runner(fun, _opts) when is_function(fun, 0) do
    {:ok, fun}
  end

  defp build_runner(other, _opts) do
    {:error, {:invalid_runner, inspect(other)}}
  end
end
