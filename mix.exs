defmodule Botica.MixProject do
  use Mix.Project

  def project do
    [
      app: :botica,
      version: "1.0.0",
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
      test_coverage: [tool: ExCoveralls],
      dialyzer: dialyzer_config()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:apero, github: "Lorenzo-SF/apero"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, ">= 1.0.0", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE.md"],
      groups_for_modules: [
        Core: [Botica, Botica.Doctor, Botica.Types],
        Execution: [Botica.Runner.Executor, Botica.Runner.Sequencer],
        Checks: [Botica.Check.Result, Botica.Check.Behaviour],
        Batteries: [
          Botica.Batteries.PostgreSQL,
          Botica.Batteries.Redis,
          Botica.Batteries.Memory,
          Botica.Batteries.Disk
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
end
