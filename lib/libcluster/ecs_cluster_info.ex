defmodule Cluster.EcsClusterInfo do
  @moduledoc """
  The goal of this module is to get us the following information:

  %{node_name => {{127,0,0,1} = ip, port}}

  for all the nodes in our ECS cluster.
  """

  use GenServer
  require Logger

  @refresh_timeout 10_000

  defmodule Container do
    defstruct [:arn, :host_port, :host_name, :ip_address]
  end

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @spec get_nodes() ::
          %{(node_name :: String.t()) => {ip :: tuple(), port :: integer()}} | no_return()
  def get_nodes() do
    GenServer.call(__MODULE__, :get_nodes)
  end

  @impl true
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
    # Required config
    region = Keyword.fetch!(config, :region)
    cluster_name = Keyword.fetch!(config, :cluster_name)
    service_name = Keyword.fetch!(config, :service_name) |> List.wrap()
    app_prefix = Keyword.fetch!(config, :app_prefix)
    container_port = Keyword.fetch!(config, :container_port)

    # Optional config
    host_name_source = Keyword.get(config, :host_name_source, :runtime_id)
    match_tags = Keyword.get(config, :match_tags)

    state
    |> Map.put(:region, region)
    |> Map.put(:cluster_name, cluster_name)
    |> Map.put(:service_name, service_name)
    |> Map.put(:app_prefix, app_prefix)
    |> Map.put(:container_port, container_port)
    |> Map.put(:host_name_source, host_name_source)
    |> Map.put(:match_tags, match_tags)
  end

  defp my_get_nodes(state) do
    region = state.region
    cluster_name = state.cluster_name
    service_name = state.service_name
    app_prefix = state.app_prefix
    container_port = state.container_port
    host_name_source = state.host_name_source
    match_tags = state.match_tags

    with {:ok, list_service_body} <- list_services(cluster_name, region),
         {:ok, service_arns} <- extract_service_arns(list_service_body),
         {:ok, task_arns} <-
           get_tasks_for_services(cluster_name, region, service_arns, service_name),
         {:ok, desc_task_body} <- describe_tasks(cluster_name, task_arns, region),
         {:ok, tasks} <- filter_tasks(desc_task_body, match_tags),
         {:ok, containers} <- extract_containers(tasks, container_port, host_name_source),
         {:ok, containers} <- set_ip_addresses(cluster_name, containers, region) do
      nodes =
        Map.new(containers, fn %Container{host_name: host_name, ip_address: ip, host_port: port} ->
         {get_node_name(app_prefix, host_name), {ip, port}}
       end)

      {:ok, nodes}
    else
      err ->
        Logger.warning(fn -> "Error #{inspect(err)} while determining nodes in cluster via ECS" end)

        {:error, []}
    end
  end

  defp get_tasks_for_services(cluster_name, region, service_arns, service_names) do
    Enum.reduce(service_names, {:ok, []}, fn service_name, acc ->
      case acc do
        {:ok, acc_tasks} ->
          with(
            {:ok, service_arn} <- find_service_arn(service_arns, service_name),
            {:ok, list_task_body} <- list_tasks(cluster_name, service_arn, region),
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

  defp list_services(cluster_name, region) do
    params = %{
      "cluster" => cluster_name
    }

    query("ListServices", params)
    |> ExAws.request(region: region)
    |> log_aws("ListServices")
    |> list_services(cluster_name, region, [])
  end

  defp list_services(
         {:ok, %{"nextToken" => next_token, "serviceArns" => service_arns}},
         cluster_name,
         region,
         accum
       )
       when not is_nil(next_token) do
    params = %{
      "cluster" => cluster_name,
      "nextToken" => next_token
    }

    query("ListServices", params)
    |> ExAws.request(region: region)
    |> log_aws("ListServices")
    |> list_services(cluster_name, region, accum ++ service_arns)
  end

  defp list_services({:ok, %{"serviceArns" => service_arns}}, _cluster_name, _region, accum) do
    {:ok, %{"serviceArns" => accum ++ service_arns}}
  end

  defp list_services({:error, message}, _cluster_name, _region, _accum) do
    {:error, message}
  end

  defp list_tasks(cluster_name, service_arn, region) do
    params = %{
      "cluster" => cluster_name,
      "serviceName" => service_arn,
      "desiredStatus" => "RUNNING"
    }

    query("ListTasks", params)
    |> ExAws.request(region: region)
    |> log_aws("ListTasks")
  end

  defp describe_tasks(cluster_name, task_arns, region) do
    params = %{
      "cluster" => cluster_name,
      "include" => ["TAGS"],
      "tasks" => task_arns
    }

    query("DescribeTasks", params)
    |> ExAws.request(region: region)
    |> log_aws("DescribeTasks")
  end

  defp describe_container_instances(cluster_name, container_arns, region) do
    params = %{
      "cluster" => cluster_name,
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

  defp filter_tasks(%{"tasks" => tasks}, nil) do
    {:ok, tasks}
  end

  defp filter_tasks(%{"tasks" => tasks}, match_tags) do
    match_tags_set =
      match_tags
      |> Enum.map(fn {key, value} -> %{"key" => key, "value" => value} end)
      |> MapSet.new()

    filtered_tasks =
      tasks
      |> Enum.filter(fn task ->
        tags =
          task
          |> Map.get("tags", [])
          |> MapSet.new()

        MapSet.subset?(match_tags_set, tags)
      end)

    {:ok, filtered_tasks}
  end

  defp filter_tasks(_, _), do: {:error, "can't filter tasks"}

  defp extract_containers(tasks, container_port, host_name_source) do
    containers =
      tasks
      |> Enum.flat_map(& extract_container_data(&1, container_port, host_name_source))
      |> Enum.filter(& &1)

    {:ok, containers}
  end

  defp extract_container_data(%{"launchType" => "FARGATE", "lastStatus" => "RUNNING"} = task, container_port, host_name_source) do
    task
    |> Map.get("containers")
    |> Enum.map(fn c ->
      arn = Map.get(c, "containerArn")
      host_name = get_host_name(c, host_name_source)
      ip_address = get_ip_address(c)

      if arn && host_name && ip_address do
        %Container{
          arn: arn,
          host_name: host_name,
          host_port: container_port,
          ip_address: ip_address
        }
      else
        nil
      end
   end)
  end

  defp extract_container_data(%{"launchType" => "EC2"} = task, container_port, host_name_source) do
    container_instance_arn = Map.get(task, "containerInstanceArn")

    task
    |> Map.get("containers")
    |> Enum.map(fn c ->
      host_name = get_host_name(c, host_name_source)
      host_port = get_host_port(c, container_port)

      if container_instance_arn && host_name && host_port do
        %Container{
          arn: container_instance_arn,
          host_name: host_name,
          host_port: host_port
        }
      else
        nil
      end
   end)
  end

  defp extract_container_data(_task, _container_port, _host_name_source), do: []

  defp set_ip_addresses(cluster_name, containers, region) do
    import SweetXml

    container_arns =
      containers
      |> Enum.map(fn
        %Container{arn: container_arn, ip_address: nil} -> container_arn
        _ -> nil
      end)
      |> Enum.uniq()
      |> Enum.filter(& &1)

    {:ok, ecs_instances} =
      case container_arns do
        [] -> {:ok, %{}}
        _ -> describe_container_instances(cluster_name, container_arns, region)
      end

    container_arn_to_ip =
      ecs_instances
      |> Map.get("containerInstances", [])
      |> Enum.map(fn i ->
        instance_id = Map.get(i, "ec2InstanceId")
        {:ok, %{body: body}} = describe_ec2_instances([instance_id], region)

        {:ok, ip_address} =
          xpath(body, ~x"//privateIpAddress/text()")
          |> :inet.parse_ipv4_address()

        {Map.get(i, "containerInstanceArn"), ip_address}
      end)
      |> Map.new()

    result =
      Enum.map(containers, fn
        %Container{ip_address: nil} = container ->
          struct(container, ip_address: Map.get(container_arn_to_ip, container.arn))

        container ->
          container
      end)

    {:ok, result}
  end

  defp get_ip_address(%{"networkInterfaces" => [%{"privateIpv4Address" => string_ip}]}) do
    {:ok, ip_address} =
      string_ip
      |> String.to_charlist()
      |> :inet.parse_ipv4_address()

    ip_address
  end

  defp get_ip_address(_container), do: nil

  defp get_host_name(%{"networkInterfaces" => [%{"privateIpv4Address" => ip_address}]}, :ip_address) do
    ip_address
  end

  defp get_host_name(%{"runtimeId" => runtime_id}, :runtime_id) do
    String.slice(runtime_id, 0..11)
  end

  defp get_host_name(_container, _), do: nil

  defp get_host_port(%{"networkBindings" => bindings}, container_port) when is_list(bindings) do
    Enum.find_value(bindings, fn
     %{"containerPort" => ^container_port, "hostPort" => h_port} -> h_port
     _ -> false
    end)
  end

  defp get_host_port(_container, _container_port), do: nil

  defp get_node_name(app_prefix, host_name) do
    :"#{app_prefix}@#{host_name}"
  end
end
