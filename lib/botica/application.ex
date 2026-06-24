defmodule Botica.Application do
  @moduledoc """
  OTP application for `Botica`.

  Starts the `Botica.Flags.Store` GenServer, which holds the ETS-backed
  feature flag registry. Reads from ETS are O(1) without going through
  the GenServer; writes go through the GenServer for serialization.

  ## Customizing the supervision tree

  Consumers can disable the default supervision by setting their own
  `mod:` in `mix.exs`:

      def application do
        [
          extra_applications: [:logger],
          mod: {MyApp.BoticaBootstrap, []}
        ]
      end
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Botica.Flags.Store
    ]

    opts = [strategy: :one_for_one, name: Botica.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
