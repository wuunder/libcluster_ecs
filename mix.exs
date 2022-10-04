defmodule ClusterEcs.MixProject do
  use Mix.Project

  def project do
    [
      app: :libcluster_ecs,
      version: "0.2.0",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      name: "Libcluster ECS",
      package: package(),
      source_url: "https://github.com/wuunder/libcluster_ecs",
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      description: "libcluster + AWS Elastic Container Service (ECS)",
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/wuunder/libcluster_ecs"
      }
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.28", only: :dev, runtime: false},
      {:ex_aws, "~> 2.1"},
      {:ex_aws_ec2, "~> 2.0"},
      {:sweet_xml, "~> 0.7.0"},
      {:libcluster, "~> 3.3"}
    ]
  end
end
