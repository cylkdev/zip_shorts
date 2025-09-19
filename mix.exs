defmodule ZipShorts.MixProject do
  use Mix.Project

  def project do
    [
      app: :zip_shorts,
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
      {:elixir_utils, git: "https://github.com/cylkdev/elixir_utils.git"},

      # cloud_cache dependencies
      {:cloud_cache, git: "https://github.com/cylkdev/cloud_cache.git"},
      {:ex_aws, "~> 2.0"},
      {:ex_aws_s3, "~> 2.0"},
      {:sweet_xml, ">= 0.0.0"},
      {:proper_case, "~> 1.0"},
      {:timex, "~> 3.0"},
      {:jason, "~> 1.0"},
      {:req, "~> 0.5"},
      {:error_message, ">= 0.0.0"},
      {:sandbox_registry, ">= 0.0.0", only: :test, runtime: false}
    ]
  end
end
