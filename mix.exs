defmodule ClusterEcs.MixProject do
  use Mix.Project

  def project do
    [
      app: :libcluster_ecs,
      version: "0.1.0",
      elixir: "~> 1.13",
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
      {:ex_aws, "~> 2.1"},
      {:ex_aws_ec2, "~> 2.0"},
      {:sweet_xml, "~> 0.7.0"}
    ]
  end
end
