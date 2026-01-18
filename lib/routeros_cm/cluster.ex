defmodule RouterosCm.Cluster do
  @moduledoc """
  The Cluster context for managing CHR nodes.
  """

  import Ecto.Query, warn: false
  alias RouterosCm.Repo
  alias RouterosCm.Cluster.Node
  alias RouterosCm.Audit

  @doc """
  Returns the list of all nodes.
  """
  def list_nodes do
    Node
    |> order_by(asc: :name)
    |> Repo.all()
  end

  @doc """
  Returns the list of active nodes (status != 'offline').
  """
  def list_active_nodes do
    Node
    |> where([n], n.status != "offline")
    |> order_by(asc: :name)
    |> Repo.all()
  end

  @doc """
  Gets a single node.

  Raises `Ecto.NoResultsError` if the Node does not exist.
  """
  def get_node!(id), do: Repo.get!(Node, id)

  @doc """
  Gets a single node, returns nil if not found.
  """
  def get_node(id), do: Repo.get(Node, id)

  @doc """
  Gets a node by name.
  """
  def get_node_by_name(name), do: Repo.get_by(Node, name: name)

  @doc """
  Gets a node by name, raising if not found.
  """
  def get_node_by_name!(name), do: Repo.get_by!(Node, name: name)

  @doc """
  Creates a node.
  """
  def create_node(attrs \\ %{}) do
    %Node{}
    |> Node.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a node with audit logging.
  """
  def create_node(scope, attrs) do
    case create_node(attrs) do
      {:ok, node} = result ->
        Audit.log_node_action(:create, node, %{
          user_id: get_user_id(scope),
          details: %{name: node.name, host: node.host}
        })

        result

      {:error, _changeset} = error ->
        Audit.log_failure(:create, :node, attrs, %{
          user_id: get_user_id(scope),
          details: %{attempted_name: attrs[:name] || attrs["name"]}
        })

        error
    end
  end

  @doc """
  Updates a node.
  """
  def update_node(%Node{} = node, attrs) do
    node
    |> Node.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates a node with audit logging.
  """
  def update_node(scope, %Node{} = node, attrs) do
    case update_node(node, attrs) do
      {:ok, updated_node} = result ->
        Audit.log_node_action(:update, updated_node, %{
          user_id: get_user_id(scope),
          details: %{name: updated_node.name, changes: Map.keys(attrs)}
        })

        result

      {:error, _changeset} = error ->
        Audit.log_failure(:update, :node, attrs, %{
          user_id: get_user_id(scope),
          resource_id: node.id,
          details: %{node_name: node.name}
        })

        error
    end
  end

  @doc """
  Deletes a node.
  """
  def delete_node(%Node{} = node) do
    Repo.delete(node)
  end

  @doc """
  Deletes a node with audit logging.
  """
  def delete_node(scope, %Node{} = node) do
    node_name = node.name
    node_id = node.id

    case delete_node(node) do
      {:ok, _deleted_node} = result ->
        Audit.log_node_action(:delete, %{
          user_id: get_user_id(scope),
          resource_id: node_id,
          details: %{node_name: node_name}
        })

        result

      {:error, _changeset} = error ->
        Audit.log_failure(:delete, :node, "delete failed", %{
          user_id: get_user_id(scope),
          resource_id: node_id,
          details: %{node_name: node_name}
        })

        error
    end
  end

  @doc """
  Tests connection to a node.
  """
  def test_connection(%Node{} = node) do
    alias RouterosCm.MikroTik.Client

    case Client.test_connection(node) do
      {:ok, _info} ->
        touch_node(node)
        {:ok, "Connection successful"}

      {:error, reason} ->
        {:error, "Connection failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking node changes.
  """
  def change_node(%Node{} = node, attrs \\ %{}) do
    Node.changeset(node, attrs)
  end

  @doc """
  Updates the last_seen_at timestamp and sets status to online.
  """
  def touch_node(%Node{} = node) do
    node
    |> Ecto.Changeset.change(%{
      last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second),
      status: "online"
    })
    |> Repo.update()
  end

  @doc """
  Sets a node's status to offline.
  """
  def set_node_offline(%Node{} = node) do
    node
    |> Ecto.Changeset.change(%{status: "offline"})
    |> Repo.update()
  end

  @doc """
  Returns cluster statistics.
  """
  def get_cluster_stats do
    total = Repo.aggregate(Node, :count, :id)
    active = Repo.one(from n in Node, where: n.status != "offline", select: count(n.id))

    %{
      total_nodes: total,
      active_nodes: active,
      offline_nodes: total - active
    }
  end

  @doc """
  Fetches health/resource information from all active nodes in parallel.

  Returns a map of node_id => resource_info where resource_info contains:
  - cpu_load: current CPU load percentage
  - free_memory: free memory in bytes
  - total_memory: total memory in bytes
  - uptime: system uptime string
  - version: RouterOS version
  - board_name: board/model name
  - architecture: CPU architecture
  """
  def fetch_cluster_health do
    alias RouterosCm.MikroTik.Client

    nodes = list_active_nodes()

    results =
      Task.async_stream(
        nodes,
        fn node ->
          case Client.get_system_resources(node) do
            {:ok, resources} ->
              {node, {:ok, parse_resources(resources)}}

            {:error, reason} ->
              {node, {:error, reason}}
          end
        end,
        max_concurrency: 10,
        timeout: 10_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, {node, result}} -> {node, result}
        {:exit, _} -> {nil, {:error, :timeout}}
      end)
      |> Enum.reject(fn {node, _} -> is_nil(node) end)
      |> Map.new(fn {node, result} -> {node.id, {node, result}} end)

    results
  end

  defp parse_resources(resources) do
    %{
      cpu_load: parse_int(resources["cpu-load"]),
      free_memory: parse_int(resources["free-memory"]),
      total_memory: parse_int(resources["total-memory"]),
      free_hdd: parse_int(resources["free-hdd-space"]),
      total_hdd: parse_int(resources["total-hdd-space"]),
      uptime: resources["uptime"],
      version: resources["version"],
      board_name: resources["board-name"],
      architecture: resources["architecture-name"],
      cpu: resources["cpu"],
      cpu_count: parse_int(resources["cpu-count"])
    }
  end

  defp parse_int(nil), do: 0
  defp parse_int(val) when is_integer(val), do: val

  defp parse_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {num, _} -> num
      :error -> 0
    end
  end

  defp get_user_id(%{user: %{id: id}}), do: id
  defp get_user_id(%{user_id: id}), do: id
  defp get_user_id(_), do: nil
end
