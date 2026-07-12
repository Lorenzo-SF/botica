defmodule Botica.Flags.Config do
  @moduledoc """
  Configuration source for feature flags. Provides defaults read from the application
  environment, allowing runtime overrides.

  ## Usage

  The flag defaults are defined in the `:botica` application env under the key
  `:flags`. They should be a keyword list of flag definitions:

      config :botica, :flags, [
        new_dashboard: [default: false, description: "new dashboard"],
        beta_search: [default: true]
      ]

  The `get/0` function returns a list of `Botica.Flags.Flag` structs with the
  supplied defaults. If no config is present, an empty list is returned.
  """

  alias Botica.Flags.Flag

  @spec get() :: [Flag.t()]
  def get do
    Application.get_env(:botica, :flags, [])
    |> Enum.map(fn
      {name, opts} when is_atom(name) and is_list(opts) ->
        Flag.new(name, opts)

      name when is_atom(name) ->
        Flag.new(name, [])

      other ->
        raise ArgumentError, "[Botica.Flags.Config] Invalid flag config entry: #{inspect(other)}"
    end)
  end
end
