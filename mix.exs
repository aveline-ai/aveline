# `gleam build` and `gleam test` write an escript named gleam@@compile.erl
# into each package's artefact directory. It is not an Erlang module, and the
# Erlang compiler would choke on it, so this tiny compiler step removes it
# before the erlang compiler runs.
defmodule Mix.Tasks.Compile.GleamClean do
  use Mix.Task.Compiler

  @impl true
  def run(_args) do
    "build/*/erlang/*/_gleam_artefacts/gleam@@compile.erl"
    |> Path.wildcard()
    |> Enum.each(&File.rm/1)

    {:noop, []}
  end
end

defmodule Aveline.MixProject do
  use Mix.Project

  def project do
    [
      app: :aveline,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      erlc_paths: [
        "build/dev/erlang/aveline/_gleam_artefacts",
        "build/dev/erlang/gleam_stdlib/_gleam_artefacts",
        "build/dev/erlang/gleam_json/_gleam_artefacts",
        "build/dev/erlang/gleeunit/_gleam_artefacts"
      ],
      erlc_include_path: "build/dev/erlang/aveline/include",
      erlc_options: [{:d, :GLEAM}],
      prune_code_paths: false,
      start_permanent: Mix.env() == :prod,
      archives: [mix_gleam: "~> 0.6"],
      compilers: [:gleam, :gleam_clean, :phoenix_live_view | Mix.compilers()],
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

  defp elixirc_paths(:test), do: ["lib", "test_support"]
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
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      # Gleam packages
      {:gleam_stdlib, "~> 0.34 or ~> 1.0"},
      {:gleam_json, "~> 3.0"},
      {:gleeunit, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      "deps.get": ["deps.get", "gleam.deps.get"],
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      # The gleam compiler step forwards positional args to deps tasks, which
      # breaks `mix test path/to/test.exs` and `mix run script.exs`; compile
      # first, then run the real task without it.
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "compile", "test --no-compile"],
      run: ["compile", "run --no-compile"],
      "assets.setup": ["cmd npm install"],
      "assets.build": ["cmd --cd assets node build.js"],
      "assets.deploy": [
        "cmd --cd assets node build.js --deploy",
        "phx.digest"
      ]
    ]
  end
end
