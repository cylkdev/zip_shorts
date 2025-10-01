defmodule ZipGz.MixProject do
  use Mix.Project

  def project do
    [
      app: :zip_gz,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      {:zstream, "~> 0.6.7"},
      {:stream_gzip, "~> 0.4.2"},
      {:nimble_options, "~> 1.1"},
      {:elixir_utils, git: "https://github.com/cylkdev/elixir_utils.git"}
    ]
  end
end
