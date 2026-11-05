defmodule Botica.Check.Behaviour do
  @moduledoc """
  Behaviour for defining health checks.

  Use this behaviour to create custom check modules with
  consistent structure and built-in support for Botica's
  health check infrastructure.

  ## Example

      defmodule MyApp.DatabaseCheck do
        use Botica.Check.Behaviour

        @impl true
        def check_def(_opts) do
          %{
            id: :database,
            name: \"Database\",
            description: \"Database connectivity\",
            priority: 1,
            tags: [:database, :critical],
            timeout: 5000,
            check: &__MODULE__.do_check/0,
            fix: &__MODULE__.do_fix/0,
            fix_command: \"sudo systemctl restart myapp-db\"
          }
        end

        defp do_check do
          # Your check logic here
          {:ok, \"Database is reachable\"}
        end

        defp do_fix do
          # Your fix logic here
          {:ok, \"Database restarted\"}
        end
      end

  Then in your config:

      Botica.Doctor.run(%{
        app_name: \"myapp\",
        checks: [MyApp.DatabaseCheck.check_def([])]
      })
  """

  @doc """
  Returns a check definition map for this check module.

  Override this callback to define your check's metadata
  and behaviour.

  ## Options

  - `timeout` - Override the default timeout for this check (in milliseconds)
  - Any other options your check implementation needs
  """
  @callback check_def(opts :: keyword()) :: Botica.Types.check_def()

  @doc """
  Optional callback to validate configuration before running checks.

  Return `:ok` if configuration is valid, or `{:error, reason}` if not.
  The default implementation always returns `:ok`.
  """
  @callback validate_config(opts :: keyword()) :: :ok | {:error, String.t()}

  @optional_callbacks validate_config: 1

  @doc """
  Macro to use this behaviour in a module.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour Botica.Check.Behaviour

      @doc """
      Convenience function that delegates to `check_def/1` with an empty opts list.
      """
      def check, do: check_def([])

      @doc """
      Default implementation of validate_config/1 - always returns :ok.
      Override if you need configuration validation.
      """
      @impl Botica.Check.Behaviour
      def validate_config(_opts), do: :ok

      defoverridable Botica.Check.Behaviour
    end
  end
end
