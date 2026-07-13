defmodule Botica.Validation do
  @moduledoc """
  Shared validation helpers for Botica configuration.

  Extracted from `Botica.Doctor` and `Botica.Runner.Executor` to
  eliminate duplicated `validate_config/1` logic.
  """

  @doc """
  Validates a Botica diagnostic configuration map.

  Returns `:ok` if valid, `{:error, reason}` otherwise.
  """
  @spec validate_config(map()) :: :ok | {:error, String.t()}
  def validate_config(config) do
    cond do
      not is_map(config) ->
        {:error, "config must be a map"}

      not is_binary(Map.get(config, :app_name)) ->
        {:error, "config.app_name must be a string"}

      not is_list(Map.get(config, :checks)) ->
        {:error, "config.checks must be a list"}

      true ->
        :ok
    end
  end
end
