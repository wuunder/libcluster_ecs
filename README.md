# ClusterEcs

Use this library to set up clustering within AWS ECS.

This library, unlike others, does not rely on configuring your nodes with `awsvpc` networking mode. Instead it queries ECS's port mappings to accomplish the goal.

## Getting started

### In AWS
Create a container port mapping (e.g. container port 7777 to host port 0, this will assign a random port).

### In your Elixir project
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
        container_port: 7777,
        runtime_id_source: :runtime_id
      ]
    ]
  ]
```

Add `Cluster.EcsClusterInfo` to your supervision tree before the cluster supervisor and provide it with your config:

```
children = [
  ...
  {Cluster.EcsClusterInfo, Application.get_env(:libcluster, :topologies)[:mycluster][:config]},
  {Cluster.Supervisor, [Application.get_env(:libcluster, :topologies), [name: MyApp.ClusterSupervisor]]}
  ...
  ]
```

If you want to use IP addresses in your node names set `runtime_id_source` to `:ip_address`

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
ecs:ListClusters
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
    {:libcluster_ecs, "~> 0.2.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/libcluster_ecs>.

