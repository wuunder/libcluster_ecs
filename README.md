# ClusterEcs

Use this library to set up clustering within AWS ECS.

This library, unlike others, does not rely on configuring your nodes with `awsvpc` networking mode. Instead it uses port mappings to accomplish the goal.

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

Configure libcluster EPMD:

```
config :libcluster_ecs,
  container_port: 7777
```

Add the following line to `rel/vm.args.eex`:

```
-epmd_module Elixir.Cluster.EPMD
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

