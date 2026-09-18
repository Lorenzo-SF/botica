defmodule Botica.MixProject do
  use Mix.Project

  def project do
    [
      app: :botica,
      version: "2.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Botica",
      description: "Environment diagnostics and health checks for Elixir.",
      source_url: "https://github.com/Lorenzo-SF/botica",
      homepage_url: "https://github.com/Lorenzo-SF/botica",
      package: [
        name: :botica,
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/Lorenzo-SF/botica"},
        maintainers: ["Lorenzo Sánchez"]
      ],
      docs: docs(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: dialyzer_config()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Botica.Application, []}
    ]
  end

  defp deps do
    [
      # Sibling deps as Hex requirements: apero / arrea are published
      # on hex.pm before botica releases, so external consumers resolve
      # everything from hex.
      {:apero, "~> 4.0", override: true},
      {:arrea, "~> 3.0", override: true},
      # Trebejo is private; CI for the public repos cannot access it.
      # Code uses Code.ensure_loaded?(Trebejo.…) guards to gracefully
      # degrade when absent. Skipped entirely from deps.
      # {:trebejo, git: "https://github.com/Lorenzo-SF/trebejo.git"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, ">= 1.0.0", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: "https://github.com/Lorenzo-SF/botica",
      homepage_url: "https://github.com/Lorenzo-SF/botica",
      source_ref: "2.1.0",
      extras: ["README.md", "docs/README.es.md", "LICENSE.md", "CHANGELOG.md"],
      groups_for_modules: [
        Core: [
          Botica,
          Botica.Doctor,
          Botica.Doctor.FlagsSummary,
          Botica.Doctor.Reporter,
          Botica.Types,
          Botica.Report,
          Botica.Validation
        ],
        Flags: [
          Botica.Flags,
          Botica.Flags.Flag,
          Botica.Flags.Store,
          Botica.Flags.Config,
          Botica.Flags.Doc,
          Botica.Flags.Persistence,
          Botica.Flags.Persistence.Disk,
          Botica.Flags.Persistence.Writer,
          Botica.Flags.Rollout
        ],
        Execution: [
          Botica.Runner.Executor,
          Botica.Runner.Sequencer,
          Botica.Runner.CheckRunner
        ],
        Runtime: [Botica.Alerts, Botica.Dashboard, Botica.Scheduler],
        Repair: [Botica.Repair.Fixer],
        Checks: [Botica.Check.Result, Botica.Check.Behaviour, Botica.Check.Group],
        Batteries: [
          Botica.Batteries.PostgreSQL,
          Botica.Batteries.Redis,
          Botica.Batteries.Memory,
          Botica.Batteries.Disk,
          Botica.Batteries.LlamaServer,
          Botica.Batteries.LlamaServer.Installer
        ]
      ]
    ]
  end

  defp dialyzer_config do
    [
      plt_file: {:no_warn, "priv/plts/botica"},
      plt_core_path: "priv/plts/core",
      plt_add_apps: [:mix],
      flags: [:error_handling, :no_opaque, :no_underspecs]
    ]
  end

  defp aliases do
    [
      "botica:config": ["run -e 'Botica.Flags.Doc.generate()'"]
    ]
  end
end
