# ClusterEcs

Use this library to set up clustering within AWS ECS.

This library, unlike others, does not rely on configuring your nodes with `awsvpc` networking mode. Instead it queries ECC's port mappings to accomplish the goal.

## Getting started

Create a container port mapping (eg, container port 7777 to host port 0, this will assign a random port).

Configure the libcluster topology:

```
config :libcluster,
  topologies: [
    mycluster: [
      strategy: Cluster.EcsStrategy,
      config: [
        cluster_name: "mycluster",
        service_name: "myservice",
        app_prefix: "myapp_prefix",
        region: "eu-west-1",
        container_port: 7777
      ]
    ]
  ]
```

Configure libcluster EPMD by setting `DISTRIBUTION_PORT` in `rel/env.sh.eex`. This needs to be an env var because this EPMD module is used during startup and application configuration is not available yet:

```
export DISTRIBUTION_PORT=7777
```

Add the following line to `rel/vm.args.eex`:

```
-epmd_module Elixir.Cluster.EPMD
```

Configure (if you haven't already) `ex_aws`. The IAM user that you configure needs the following permissions:

```
ecs:ListClusters"
ecs:ListServices
ecs:ListTasks
ecs:DescribeTasks
ecs:DescribeContainerInstances
ec2:DescribeInstances
```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `libcluster_ecs` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:libcluster_ecs, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/libcluster_ecs>.

