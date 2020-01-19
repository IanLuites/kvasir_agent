defmodule Kvasir.Agent.MixProject do
  use Mix.Project
  @version "0.0.3"

  def project do
    [
      app: :kvasir_agent,
      description: "Kvasir agent extension to allow for aggregated state processes.",
      version: @version,
      elixir: "~> 1.7",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),

      # Testing
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      # dialyzer: [ignore_warnings: "dialyzer.ignore-warnings", plt_add_deps: true],

      # Docs
      name: "kvasir_agent",
      source_url: "https://github.com/IanLuites/kvasir_agent",
      homepage_url: "https://github.com/IanLuites/kvasir_agent",
      docs: [
        main: "readme",
        extras: ["README.md"]
      ]
    ]
  end

  def package do
    [
      name: :kvasir_agent,
      maintainers: ["Ian Luites"],
      licenses: ["MIT"],
      files: [
        # Elixir
        "lib/kvasir",
        "lib/agent",
        "lib/agent.ex",
        ".formatter.exs",
        "mix.exs",
        "README*",
        "LICENSE*"
      ],
      links: %{
        "GitHub" => "https://github.com/IanLuites/kvasir_agent"
      }
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:kvasir, git: "https://github.com/IanLuites/kvasir", branch: "release/v1.0"},
      {:httpx, "~> 0.0.16", optional: true}
    ]
  end
end
