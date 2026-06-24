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
    * `:rollout` — `0..100` percentage of users that get the feature when
      `enabled: true`. `nil` means binary on/off (no gradual rollout).
    * `:created_at` — When the flag was first defined
    * `:updated_at` — Last modification timestamp
  """

  @type t :: %__MODULE__{
          name: atom(),
          enabled: boolean(),
          default: boolean(),
          description: String.t() | nil,
          rollout: non_neg_integer() | nil,
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
    # Microsecond precision so back-to-back defines get distinct timestamps
    # (otherwise ordering / "preserves created_at" tests are flaky).
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

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

  # Clamp rollout to 0..100. nil stays nil.
  defp normalize_rollout(nil), do: nil
  defp normalize_rollout(pct) when is_integer(pct) and pct >= 0 and pct <= 100, do: pct

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
end
