defmodule Aveline.MixProject do
  use Mix.Project

  def project do
    [
      app: :aveline,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Aveline.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.8"},
      {:phoenix_ecto, "~> 4.6"},
      {:phoenix_html, "~> 4.2"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_live_reload, "~> 1.6", only: :dev},
      {:ecto_sql, "~> 3.12"},
      {:postgrex, ">= 0.0.0"},
      {:myxql, "~> 0.7"},
      {:cloak_ecto, "~> 1.3"},
      {:floki, ">= 0.36.0", only: :test},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:swoosh, "~> 1.18"},
      {:finch, "~> 0.19"},
      {:telemetry_metrics, "~> 1.1"},
      {:telemetry_poller, "~> 1.1"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.4"},
      {:dns_cluster, "~> 0.2"},
      {:bandit, "~> 1.6"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:accessible, "~> 0.3"},
      {:tzdata, "~> 1.1"},
      {:corsica, "~> 2.1"},
      {:sentry, "~> 12.0"},
      {:hackney, "~> 1.20"},
      {:oban, "~> 2.19"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["esbuild.install --if-missing"],
      "assets.build": ["esbuild aveline"],
      "assets.deploy": [
        "esbuild.install --if-missing",
        "esbuild aveline --minify",
        "phx.digest"
      ]
    ]
  end
end
