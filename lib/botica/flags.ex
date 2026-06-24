defmodule Botica.Flags do
  @moduledoc """
  Feature flags for Elixir with deterministic per-entity rollouts.

  ## Why this exists

  Botica already deals with runtime diagnostics and configuration. Feature
  flags are a natural extension: they let you toggle behaviour at runtime
  without redeploying, and they let you roll features out to a percentage
  of users safely.

  The implementation is intentionally tiny:
    - **Storage**: ETS (`:set`, `:public`, `read_concurrency: true`).
      No external service, no Redis, no Postgres.
    - **Writes**: Serialised through `Botica.Flags.Store` (GenServer) to
      avoid race conditions.
    - **Reads**: O(1) direct ETS lookup via the Store — no GenServer
      round-trip on the hot path.
    - **Rollout**: `:erlang.phash2/2` for deterministic bucketing —
      `enabled?(name, for: user_id)` is stable across restarts.

  ## Quick start

      # 1. Define flags (typically at boot, e.g. in your Application.start)
      Botica.Flags.define(:new_dashboard, default: false)
      Botica.Flags.define(:beta_search, default: true)
      Botica.Flags.define(:rate_limiting, default: false, rollout: 25)

      # 2. Query at runtime
      Botica.Flags.enabled?(:new_dashboard)                    # => false
      Botica.Flags.enabled?(:beta_search)                      # => true
      Botica.Flags.enabled?(:rate_limiting, for: user_id)      # => true / false deterministically

      # 3. Mutate at runtime (serialised via GenServer)
      Botica.Flags.enable(:new_dashboard)
      Botica.Flags.disable(:new_dashboard)
      Botica.Flags.set(:rate_limiting, rollout: 50)

      # 4. Introspection
      Botica.Flags.all()        # => [%Flag{}, ...]
      Botica.Flags.get(:foo)     # => {:ok, %Flag{}} | :error
      Botica.Flags.count()       # => 3

  ## Rollout semantics

  When `rollout: N` is set (0 ≤ N ≤ 100) AND `enabled: true`, the flag is
  on for the first N percent of entities, where "entity" is any term you
  pass as `for:` (typically a user_id or session_id). The bucketing is
  deterministic:

      iex> Botica.Flags.define(:r, default: false, rollout: 50)
      iex> Botica.Flags.enable(:r)
      iex> Botica.Flags.enabled?(:r, for: "user_42")
      true
      iex> Botica.Flags.enabled?(:r, for: "user_42")  # always the same
      true

  When `rollout: nil` (the default), the flag is binary on/off and the
  `for:` option is ignored.
  """

  alias Botica.Flags.{Flag, Store}

  # ---------------------------------------------------------------------------
  # Define / mutate
  # ---------------------------------------------------------------------------

  @doc """
  Defines a new flag or updates an existing one.

  ## Options

    * `:default` — value when flag is not enabled (default `false`)
    * `:description` — optional human-readable note
    * `:rollout` — `0..100` percentage when enabled (default `nil`)

  Returns `:ok` always (write is sync via GenServer.call).

  ## Examples

      Botica.Flags.define(:new_dashboard, default: false)
      Botica.Flags.define(:beta_search, default: true, description: "WIP")
      Botica.Flags.define(:rate_limiting, default: false, rollout: 25)
  """
  @spec define(atom(), keyword()) :: :ok
  def define(name, opts \\ []) when is_atom(name) and is_list(opts) do
    # Preserve the existing created_at if the flag is being redefined.
    created_at =
      case Store.get(name) do
        {:ok, existing} -> existing.created_at
        :error -> nil
      end

    flag = Flag.new(name, opts)
    flag = if created_at, do: %{flag | created_at: created_at}, else: flag

    Store.put(flag)
  end

  @doc """
  Forces a flag to enabled regardless of its rollout percentage.

  The flag is also created with default = true if it didn't exist.
  """
  @spec enable(atom()) :: :ok
  def enable(name) when is_atom(name) do
    case Store.get(name) do
      {:ok, %Flag{} = existing} ->
        Store.put(%{existing | enabled: true})

      :error ->
        define(name, default: true, enabled: true)
    end
  end

  @doc """
  Forces a flag to disabled. Existing rollout percentages are preserved.
  """
  @spec disable(atom()) :: :ok
  def disable(name) when is_atom(name) do
    case Store.get(name) do
      {:ok, %Flag{} = existing} ->
        Store.put(%{existing | enabled: false})

      :error ->
        define(name, default: false, enabled: false)
    end
  end

  @doc """
  Updates one or more attributes of an existing flag.

  Accepted keys: `:enabled`, `:rollout`, `:description`, `:default`.

  ## Examples

      Botica.Flags.set(:rate_limiting, rollout: 50)
      Botica.Flags.set(:new_dashboard, enabled: true, description: "Rolled out to all")
  """
  @spec set(atom(), keyword()) :: :ok | {:error, :not_found}
  def set(name, opts) when is_atom(name) and is_list(opts) do
    case Store.get(name) do
      {:ok, %Flag{} = existing} ->
        updates =
          opts
          |> Keyword.take([:enabled, :rollout, :description, :default])
          |> Enum.into(%{})

        Store.put(Map.merge(existing, updates))

      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Removes a flag from the registry.
  """
  @spec delete(atom()) :: :ok
  def delete(name) when is_atom(name), do: Store.delete(name)

  # ---------------------------------------------------------------------------
  # Query
  # ---------------------------------------------------------------------------

  @doc """
  Returns whether a flag is enabled. Two-arity version takes a deterministic
  `for:` argument used for rollout bucketing.

  Behaviour:
    * If the flag is not defined → returns its default value (or `false`).
    * If the flag is defined and `enabled: false` → returns `false`.
    * If the flag is defined, `enabled: true`, and `rollout: nil`
      → returns `true`.
    * If the flag is defined, `enabled: true`, and `rollout: P`
      → returns `true` for the first P% of entities (deterministic hash).

  ## Examples

      iex> Botica.Flags.define(:a, default: false)
      iex> Botica.Flags.enabled?(:a)
      false

      iex> Botica.Flags.define(:b, default: true)
      iex> Botica.Flags.enabled?(:b)
      true
  """
  @spec enabled?(atom()) :: boolean()
  def enabled?(name) when is_atom(name) do
    case Store.get(name) do
      {:ok, %Flag{enabled: true}} -> true
      {:ok, %Flag{enabled: false}} -> false
      :error -> false
    end
  end

  @spec enabled?(atom(), keyword()) :: boolean()
  def enabled?(name, opts) when is_atom(name) and is_list(opts) do
    entity = Keyword.get(opts, :for)

    case Store.get(name) do
      {:ok, %Flag{enabled: true, rollout: nil}} ->
        true

      {:ok, %Flag{enabled: true, rollout: pct}} when is_integer(pct) and pct >= 0 ->
        bucket_for(name, entity) < pct

      {:ok, %Flag{enabled: false}} ->
        false

      :error ->
        false
    end
  end

  @doc """
  Returns the flag struct or `:error`.
  """
  @spec get(atom()) :: {:ok, Flag.t()} | :error
  def get(name) when is_atom(name), do: Store.get(name)

  @doc """
  Returns all registered flags (most recently updated first).
  """
  @spec all() :: [Flag.t()]
  def all do
    Store.all()
    |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})
  end

  @doc """
  Total number of registered flags.
  """
  @spec count() :: non_neg_integer()
  def count, do: Store.count()

  # ---------------------------------------------------------------------------
  # Internal
  # ---------------------------------------------------------------------------

  # Stable, deterministic bucket in 0..99 for any term.
  # Using :erlang.phash2 with range 100 keeps the same user in the same
  # bucket across restarts (unlike :rand).
  @spec bucket_for(atom(), term()) :: non_neg_integer()
  defp bucket_for(flag_name, entity) do
    :erlang.phash2({flag_name, entity}, 100)
  end
end
