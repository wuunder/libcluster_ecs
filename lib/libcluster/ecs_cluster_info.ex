defmodule Cluster.EcsClusterInfo do
  @moduledoc """
  The goal of this module is to get us the following information:

  %{node_name => {{127,0,0,1} = ip, port}}

  for all the nodes in our ECS cluster.
  """

  use GenServer
  require Logger

  @refresh_timeout 10_000

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @spec get_nodes() :: %{(node_name :: String.t()) => {ip :: tuple(), port :: integer()}}
  def get_nodes(config \\ []) do
    case GenServer.whereis(__MODULE__) do
      nil ->
        {:ok, nodes} = my_get_nodes(set_config(config, %{}))
        nodes

      _ ->
        GenServer.call(__MODULE__, :get_nodes)
    end
  end

  @impl true
  def init(nil) do
    {:ok, nil}
  end

  def init(config) do
    set_refresh()

    state = set_config(config, %{})

    {:ok, nodes} = my_get_nodes(state)

    {:ok, state |> Map.put(:nodes, nodes)}
  end

  @impl true
  def handle_call(:get_nodes, _from, state) do
    {:reply, Map.get(state, :nodes, %{}), state}
  end

  @impl true
  def handle_info(:refresh, state) do
    {:ok, nodes} = my_get_nodes(state)

    set_refresh()
    {:noreply, state |> Map.put(:nodes, nodes)}
  end

  defp set_refresh() do
    Process.send_after(self(), :refresh, @refresh_timeout)
  end

  defp set_config(config, state) do
    region = Keyword.fetch!(config, :region)
    cluster = Keyword.fetch!(config, :cluster)
    service_name = Keyword.fetch!(config, :service_name) |> List.wrap()
    app_prefix = Keyword.fetch!(config, :app_prefix)
    container_port = Keyword.fetch!(config, :container_port)

    state
    |> Map.put(:region, region)
    |> Map.put(:cluster, cluster)
    |> Map.put(:service_name, service_name)
    |> Map.put(:app_prefix, app_prefix)
    |> Map.put(:container_port, container_port)
  end

  defp my_get_nodes(state) do
    region = state.region
    cluster = state.cluster
    service_name = state.service_name
    app_prefix = state.app_prefix
    container_port = state.container_port

    with {:ok, list_service_body} <- list_services(cluster, region),
         {:ok, service_arns} <- extract_service_arns(list_service_body),
         {:ok, task_arns} <- get_tasks_for_services(cluster, region, service_arns, service_name),
         {:ok, desc_task_body} <- describe_tasks(cluster, task_arns, region),
         {:ok, arns_ports} <- extract_arns_ports(desc_task_body, container_port),
         {:ok, ips_ports} <- extract_ips_ports(cluster, arns_ports, region) do
      {:ok,
       Map.new(ips_ports, fn {runtime_id, ip, port} ->
         {runtime_id_to_nodename(runtime_id, app_prefix), {ip, port}}
       end)}
    else
      err ->
        Logger.warn(fn -> "Error #{inspect(err)} while determining nodes in cluster via ECS" end)

        {:error, []}
    end
  end

  defp get_tasks_for_services(cluster, region, service_arns, service_names) do
    Enum.reduce(service_names, {:ok, []}, fn service_name, acc ->
      case acc do
        {:ok, acc_tasks} ->
          with(
            {:ok, service_arn} <- find_service_arn(service_arns, service_name),
            {:ok, list_task_body} <- list_tasks(cluster, service_arn, region),
            {:ok, task_arns} <- extract_task_arns(list_task_body)
          ) do
            {:ok, acc_tasks ++ task_arns}
          end

        other ->
          other
      end
    end)
  end

  defp log_aws(response, request_type) do
    Logger.debug("ExAws #{request_type} response: #{inspect(response)}")
    response
  end

  defp list_services(cluster, region) do
    params = %{
      "cluster" => cluster
    }

    query("ListServices", params)
    |> ExAws.request(region: region)
    |> log_aws("ListServices")
    |> list_services(cluster, region, [])
  end

  defp list_services(
         {:ok, %{"nextToken" => next_token, "serviceArns" => service_arns}},
         cluster,
         region,
         accum
       )
       when not is_nil(next_token) do
    params = %{
      "cluster" => cluster,
      "nextToken" => next_token
    }

    query("ListServices", params)
    |> ExAws.request(region: region)
    |> log_aws("ListServices")
    |> list_services(cluster, region, accum ++ service_arns)
  end

  defp list_services({:ok, %{"serviceArns" => service_arns}}, _cluster, _region, accum) do
    {:ok, %{"serviceArns" => accum ++ service_arns}}
  end

  defp list_services({:error, message}, _cluster, _region, _accum) do
    {:error, message}
  end

  defp list_tasks(cluster, service_arn, region) do
    params = %{
      "cluster" => cluster,
      "serviceName" => service_arn,
      "desiredStatus" => "RUNNING"
    }

    query("ListTasks", params)
    |> ExAws.request(region: region)
    |> log_aws("ListTasks")
  end

  defp describe_tasks(cluster, task_arns, region) do
    params = %{
      "cluster" => cluster,
      "tasks" => task_arns
    }

    query("DescribeTasks", params)
    |> ExAws.request(region: region)
    |> log_aws("DescribeTasks")
  end

  # EC2_IID=$(aws ecs describe-container-instances --cluster ${CLUSTER} --container-instances ${CONTAINER_ARN} --output text --query 'containerInstances[0].ec2InstanceId')
  defp describe_container_instances(cluster, container_arns, region) do
    params = %{
      "cluster" => cluster,
      "containerInstances" => container_arns
    }

    query("DescribeContainerInstances", params)
    |> ExAws.request(region: region)
    |> log_aws("DescribeContainerInstances")
  end

  defp describe_ec2_instances(instance_ids, region) do
    ExAws.EC2.describe_instances(instance_ids: instance_ids)
    |> ExAws.request(region: region)
    |> log_aws("EC2:DescribeInstances")
  end

  @namespace "AmazonEC2ContainerServiceV20141113"
  defp query(action, params) do
    ExAws.Operation.JSON.new(
      :ecs,
      %{
        data: params,
        headers: [
          {"accept-encoding", "identity"},
          {"x-amz-target", "#{@namespace}.#{action}"},
          {"content-type", "application/x-amz-json-1.1"}
        ]
      }
    )
  end

  defp extract_task_arns(%{"taskArns" => arns}), do: {:ok, arns}
  defp extract_task_arns(_), do: {:error, "unknown task arns response"}

  defp extract_service_arns(%{"serviceArns" => arns}), do: {:ok, arns}
  defp extract_service_arns(_), do: {:error, "unknown service arns response"}

  defp find_service_arn(service_arns, service_name) when is_list(service_arns) do
    with {:ok, regex} <- Regex.compile(service_name) do
      service_arns
      |> Enum.find(&Regex.match?(regex, &1))
      |> case do
        nil ->
          Logger.error("no service matching #{service_name} found")
          {:error, "no service matching #{service_name} found"}

        arn ->
          {:ok, arn}
      end
    end
  end

  defp find_service_arn(_, _), do: {:error, "no service arns returned"}

  defp extract_arns_ports(%{"tasks" => tasks}, container_port) do
    arns_ports =
      tasks
      |> Enum.flat_map(fn t ->
        container_instance_arn = Map.get(t, "containerInstanceArn")

        Map.get(t, "containers")
        |> Enum.map(fn c -> {container_instance_arn, c} end)
      end)
      |> Enum.map(fn {container_instance_arn, c} ->
        runtime_id =
          case Map.get(c, "runtimeId") do
            nil -> nil
            string -> String.slice(string, 0..11)
          end

        host_port =
          Map.get(c, "networkBindings")
          |> Enum.find_value(fn
            %{"containerPort" => ^container_port, "hostPort" => h_port} ->
              h_port

            _ ->
              false
          end)

        if container_instance_arn && runtime_id && host_port do
          {container_instance_arn, runtime_id, host_port}
        else
          nil
        end
      end)
      |> Enum.filter(& &1)

    {:ok, arns_ports}
  end

  defp extract_arns_ports(_, _), do: {:error, "can't extract ips"}

  defp extract_ips_ports(cluster, arns_ports, region) do
    import SweetXml

    container_arns =
      Enum.map(arns_ports, fn {container_arn, _runtime_id, _host_port} -> container_arn end)
      |> Enum.uniq()

    {:ok, ecs_instances} =
      case container_arns do
        [] ->
          {:ok, []}

        _ ->
          describe_container_instances(cluster, container_arns, region)
      end

    container_arn_to_ip =
      Map.get(ecs_instances, "containerInstances")
      |> Enum.map(fn i ->
        instance_id = Map.get(i, "ec2InstanceId")
        {:ok, %{body: body}} = describe_ec2_instances([instance_id], region)

        {:ok, ip_address} =
          xpath(body, ~x"//privateIpAddress/text()")
          |> :inet.parse_ipv4_address()

        {Map.get(i, "containerInstanceArn"), ip_address}
      end)
      |> Map.new()

    {:ok,
     Enum.map(arns_ports, fn {container_arn, runtime_id, host_port} ->
       ip_address = Map.get(container_arn_to_ip, container_arn)
       {runtime_id, ip_address, host_port}
     end)}
  end

  defp runtime_id_to_nodename(runtime_id, app_prefix) do
    :"#{app_prefix}@#{runtime_id}"
  end
end
