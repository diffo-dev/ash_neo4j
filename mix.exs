defmodule AshNeo4j.MixProject do
  @moduledoc false
  use Mix.Project

  @version "0.2.5"
  @name "AshNeo4j"
  @description "Ash DataLayer for Neo4j"
  @github_url "https://github.com/diffo-dev/ash_neo4j"

  def project do
    [
      app: :ash_neo4j,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      package: package(),
      deps: deps(),
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.github": :test
      ],
      elixirc_paths: elixirc_paths(Mix.env()),
      docs: &docs/0,
      dialyzer: [plt_add_apps: [:jason, :poison, :mix], ignore_warnings: ".dialyzer_ignore.exs"],
      test_coverage: [
        tool: ExCoveralls,
        summary: [
          threshold: 70
        ]
      ],
      consolidate_protocols: Mix.env() == :prod,
      aliases: aliases(),
      # ex_doc
      name: @name,
      source_url: @github_url,
      homepage_url: "https://diffo.dev/diffo/ash_neo4j",
      docs: [main: "readme", extras: ["README.md"]],
      # hex.pm stuff
      description: @description,
      package: [
        name: "ash_neo4j",
        licenses: ["MIT"],
        files: ["lib", "mix.exs", "README*", "VERSION*"],
        maintainers: ["Matt Beanland"],
        links: %{
          "GitHub" => @github_url,
          "Author's home page" => "https://www.diffo.dev"
        }
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def docs do
    [
      homepage_url: @github_url,
      source_url: @github_url,
      source_ref: "v#{@version}",
      main: "readme",
      logo: "logos/diffo.jpg",
      extras: [
        "README.md": [title: "Guide"],
        "LICENSE.md": [title: "License"],
        "documentation/dsls/DSL-AshNeo4j.DataLayer.md": [
          title: "DSL: AshNeo4j.DataLayer",
          search_data: Spark.Docs.search_data_for(AshNeo4j.DataLayer)
        ]
      ]
    ]
  end

  defp package do
    [
      name: :ash_neo4j,
      licenses: ["MIT"],
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* documentation),
      links: %{
        GitHub: "https://github.com/diffo-dev/ash_neo4j"
      }
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ash, ash_version("~> 3.5")},
      {:ash_state_machine, "~> 0.2.8", only: [:dev, :test]},
      {:boltx, ">= 0.0.6"},
      {:igniter, "~> 0.5", only: [:dev, :test]},
      {:ex_doc, "~> 0.37", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.12", only: [:dev, :test]},
      {:git_ops, "~> 2.7", only: [:dev], runtime: false},
      {:credo, ">= 1.7.3", only: [:dev, :test], runtime: false},
      {:dialyxir, ">= 1.4.3", only: [:dev, :test], runtime: false},
      {:sobelow, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18.0", only: [:dev, :test]},
      {:mix_audit, ">= 0.0.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp ash_version(default_version) do
    case System.get_env("ASH_VERSION") do
      nil -> default_version
      "local" -> [path: "../ash"]
      "main" -> [git: "https://github.com/ash-project/ash.git"]
      version -> "~> #{version}"
    end
  end

  defp aliases do
    [
      sobelow: "sobelow --skip",
      credo: "credo --strict",
      docs: [
        "spark.cheat_sheets",
        "docs",
        "spark.replace_doc_links"
      ],
      "spark.formatter": "spark.formatter --extensions AshNeo4j.DataLayer",
      "spark.cheat_sheets": "spark.cheat_sheets --extensions AshNeo4j.DataLayer"
    ]
  end
end
