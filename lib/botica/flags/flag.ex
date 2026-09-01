defmodule Botica.Flags.Flag do
  @moduledoc """
  Struct representing a single feature flag.

  ## Fields

    * `:name` — Atom identifier (e.g. `:new_dashboard`)
    * `:enabled` — Whether the flag is on. For rollout flags this is the
      master switch; individual users are gated by the rollout percentage.
    * `:default` — Fallback value when the flag is queried but not defined.
      Most flags use `default: false`; if you want safe-by-default for
      risky features, use `default: false`.
    * `:description` — Optional human-readable explanation
    * `:rollout` — Gradual rollout definition. Either a legacy integer
      `0..100` percentage, or a map:
        - `%{type: :percentage, value: 25}` — first 25% of entities
        - `%{type: :user_list, users: ["lorenzo"]}` — explicit user list
        - `%{type: :attribute, key: "tenant", values: ["acme"]}` — match
          a context attribute against allowed values
      `nil` means binary on/off (no gradual rollout).
    * `:created_at` — When the flag was first defined
    * `:updated_at` — Last modification timestamp
  """

  @type rollout_t ::
          non_neg_integer()
          | %{type: :percentage, value: non_neg_integer()}
          | %{type: :user_list, users: [String.t()]}
          | %{type: :attribute, key: String.t(), values: [String.t()]}

  @type t :: %__MODULE__{
          name: atom(),
          enabled: boolean(),
          default: boolean(),
          description: String.t() | nil,
          rollout: rollout_t() | nil,
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @enforce_keys [:name]
  defstruct [
    :name,
    :description,
    :created_at,
    :updated_at,
    enabled: false,
    default: false,
    rollout: nil
  ]

  @doc """
  Creates a new Flag with the given attributes. Fills timestamps automatically.

  ## Examples

      iex> Botica.Flags.Flag.new(:beta, default: false)
      %Botica.Flags.Flag{name: :beta, enabled: false, default: false, ...}

      iex> Botica.Flags.Flag.new(:rate_limiting, default: false, rollout: 25)
      %Botica.Flags.Flag{name: :rate_limiting, rollout: 25, ...}
  """
  @spec new(atom(), keyword()) :: t()
  def new(name, opts \\ []) when is_atom(name) and is_list(opts) do
    # Use monotonic_time with microsecond precision so back-to-back
    # defines get distinct timestamps (DateTime.utc_now/0 can return
    # the same value twice in a row on fast systems).
    now =
      :erlang.system_time(:microsecond)
      |> DateTime.from_unix!(:microsecond)

    %__MODULE__{
      name: name,
      enabled: Keyword.get(opts, :enabled, Keyword.get(opts, :default, false)),
      default: Keyword.get(opts, :default, false),
      description: Keyword.get(opts, :description),
      rollout: normalize_rollout(Keyword.get(opts, :rollout)),
      created_at: now,
      updated_at: now
    }
  end

  # Clamp integer rollout to 0..100 (legacy format). nil stays nil.
  # Map rollouts are validated structurally and passed through.
  defp normalize_rollout(nil), do: nil

  defp normalize_rollout(pct) when is_integer(pct) and pct >= 0 and pct <= 100, do: pct

  defp normalize_rollout(%{type: :percentage, value: value})
       when is_integer(value) and value >= 0 and value <= 100 do
    %{type: :percentage, value: value}
  end

  defp normalize_rollout(%{type: :user_list, users: users}) when is_list(users) do
    %{type: :user_list, users: users}
  end

  defp normalize_rollout(%{type: :attribute, key: key, values: values})
       when is_binary(key) and is_list(values) do
    %{type: :attribute, key: key, values: values}
  end

  defp normalize_rollout(pct) when is_integer(pct) and pct > 100 do
    require Logger
    Logger.warning("[Botica.Flags] rollout #{pct} > 100, clamped to 100")
    100
  end

  defp normalize_rollout(pct) when is_integer(pct) and pct < 0 do
    require Logger
    Logger.warning("[Botica.Flags] rollout #{pct} < 0, clamped to 0")
    0
  end

  defp normalize_rollout(%{type: :percentage, value: value}) when is_integer(value) and value > 100 do
    require Logger
    Logger.warning("[Botica.Flags] rollout percentage #{value} > 100, clamped to 100")
    %{type: :percentage, value: 100}
  end

  defp normalize_rollout(%{type: :percentage, value: value}) when is_integer(value) and value < 0 do
    require Logger
    Logger.warning("[Botica.Flags] rollout percentage #{value} < 0, clamped to 0")
    %{type: :percentage, value: 0}
  end

  defp normalize_rollout(other) do
    require Logger
    Logger.warning("[Botica.Flags] invalid rollout definition ignored: #{inspect(other)}")
    nil
  end
end
