defmodule RouterosCmWeb.API.V1.ClusterController do
  @moduledoc """
  API controller for cluster-wide operations and health monitoring.
  """
  use RouterosCmWeb, :controller

  import RouterosCmWeb.API.V1.Base

  alias RouterosCm.Cluster

  plug :require_scope, "nodes:read" when action in [:health, :stats]

  @doc """
  Get cluster health information from all active nodes.

  GET /api/v1/cluster/health
  """
  def health(conn, _params) do
    health_data = Cluster.fetch_cluster_health()

    nodes_health =
      health_data
      |> Enum.map(fn {node_id, {node, result}} ->
        {node_id, format_node_health(node, result)}
      end)
      |> Map.new()

    summary = calculate_summary(health_data)

    json_response(conn, %{
      nodes: nodes_health,
      summary: summary
    })
  end

  @doc """
  Get cluster statistics.

  GET /api/v1/cluster/stats
  """
  def stats(conn, _params) do
    stats = Cluster.get_cluster_stats()

    json_response(conn, %{
      total_nodes: stats.total_nodes,
      active_nodes: stats.active_nodes,
      offline_nodes: stats.offline_nodes
    })
  end

  # Private helpers

  defp format_node_health(node, {:ok, resources}) do
    memory_percent =
      if resources.total_memory > 0 do
        ((resources.total_memory - resources.free_memory) / resources.total_memory * 100)
        |> Float.round(1)
      else
        0
      end

    hdd_percent =
      if resources.total_hdd > 0 do
        ((resources.total_hdd - resources.free_hdd) / resources.total_hdd * 100)
        |> Float.round(1)
      else
        0
      end

    %{
      name: node.name,
      status: "healthy",
      cpu_load: resources.cpu_load,
      memory: %{
        free: resources.free_memory,
        total: resources.total_memory,
        percent_used: memory_percent
      },
      storage: %{
        free: resources.free_hdd,
        total: resources.total_hdd,
        percent_used: hdd_percent
      },
      uptime: resources.uptime,
      version: resources.version,
      board_name: resources.board_name,
      architecture: resources.architecture,
      cpu: resources.cpu,
      cpu_count: resources.cpu_count
    }
  end

  defp format_node_health(node, {:error, reason}) do
    %{
      name: node.name,
      status: "unhealthy",
      error: format_error(reason)
    }
  end

  defp format_error(:timeout), do: "Connection timeout"
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp calculate_summary(health_data) do
    {healthy, unhealthy} =
      health_data
      |> Enum.split_with(fn {_node_id, {_node, result}} ->
        match?({:ok, _}, result)
      end)

    %{
      total_nodes: map_size(health_data),
      healthy_nodes: length(healthy),
      unhealthy_nodes: length(unhealthy)
    }
  end
end
