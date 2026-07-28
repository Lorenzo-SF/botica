defmodule Botica.Doctor.FlagsSummary do
  @moduledoc """
  Formats `Botica.Flags` registry data into human-readable summaries.

  Used by `Botica.Doctor` CLI / REPL wrappers to produce diagnostic banners.
  """

  alias Botica.Flags

  @doc """
  Returns a diagnostic snapshot of the current `Botica.Flags` registry.

  Shape:

      %{
        count: 3,
        flags: [
          %{name: :beta_search, status: :enabled, default: true, rollout: nil},
          %{name: :new_dashboard, status: :disabled, default: false, rollout: nil},
          %{name: :rate_limiting, status: :rollout, default: false, rollout: 25}
        ]
      }
  """
  @spec snapshot() :: %{
          required(:count) => non_neg_integer(),
          required(:flags) => [map()]
        }
  def snapshot do
    summary =
      Flags.all()
      |> Enum.map(fn flag ->
        status =
          cond do
            flag.enabled and is_integer(flag.rollout) -> :rollout
            flag.enabled -> :enabled
            true -> :disabled
          end

        %{
          name: flag.name,
          status: status,
          default: flag.default,
          rollout: flag.rollout,
          description: flag.description
        }
      end)

    %{count: length(summary), flags: summary}
  end

  @doc """
  Formats the `snapshot/0` output as a human-readable string.

  Returns an empty string when no flags are defined.

  ## Example

      Flags (3 defined):
        ✓ beta_search     enabled  (default: true)
        ✗ new_dashboard   disabled (default: false)
        ~ rate_limiting   rollout 25% (default: false)
  """
  @spec format() :: String.t()
  def format do
    case snapshot() do
      %{count: 0} ->
        ""

      %{count: count, flags: flags} ->
        rows =
          Enum.map_join(flags, "\n", fn flag ->
            icon = icon_for(flag.status)
            state = state_for(flag.status, flag.rollout)
            default = "(default: #{flag.default})"
            "  #{icon} #{pad(flag.name)}  #{pad(state)}  #{default}"
          end)

        "Flags (#{count} defined):\n#{rows}"
    end
  end

  defp icon_for(:enabled), do: "✓"
  defp icon_for(:disabled), do: "✗"
  defp icon_for(:rollout), do: "~"

  defp state_for(:rollout, pct) when is_integer(pct), do: "rollout #{pct}%"
  defp state_for(:enabled, _), do: "enabled"
  defp state_for(:disabled, _), do: "disabled"

  defp pad(name) when is_atom(name), do: name |> Atom.to_string() |> String.pad_trailing(16)
  defp pad(name) when is_binary(name), do: String.pad_trailing(name, 16)
  defp pad(name), do: name |> to_string() |> String.pad_trailing(16)
end
