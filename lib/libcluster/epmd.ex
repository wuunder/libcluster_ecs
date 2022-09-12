defmodule Cluster.EPMD do
  alias Cluster.EcsClusterInfo
  require Logger

  @magic_version 5

  def start_link do
    :erl_epmd.start_link()
  end

  def register_node(name, port, family) do
    :erl_epmd.register_node(name, port, family)
  end

  def listen_port_please(_name, _hostname) do
    container_port = System.get_env("DISTRIBUTION_PORT") |> String.to_integer()
    {:ok, container_port}
  end

  @spec address_please(charlist(), charlist(), atom()) ::
          {:ok, :inet.ip_address(), integer(), integer()} | {:error, term()}
  def address_please(name, hostname, family) do
    nodename = :"#{name}@#{hostname}"

    case EcsClusterInfo.get_nodes() do
      %{^nodename => {ip, port}} -> {:ok, ip, port, @magic_version}
      _ -> :erl_epmd.address_please(name, hostname, family)
    end
  end

  def names(hostname) do
    :erl_epmd.names(hostname)
  end
end
