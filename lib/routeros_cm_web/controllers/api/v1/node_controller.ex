defmodule RouterosCmWeb.API.V1.NodeController do
  @moduledoc """
  API controller for managing cluster nodes.
  """
  use RouterosCmWeb, :controller

  import RouterosCmWeb.API.V1.Base

  alias RouterosCm.Cluster

  plug :require_scope, "nodes:read" when action in [:index, :show]
  plug :require_scope, "nodes:write" when action in [:create, :update, :delete, :test]

  @doc """
  List all nodes in the cluster.

  GET /api/v1/nodes
  """
  def index(conn, _params) do
    nodes = Cluster.list_nodes()
    json_response(conn, Enum.map(nodes, &node_to_json/1))
  end

  @doc """
  Get a specific node by ID.

  GET /api/v1/nodes/:id
  """
  def show(conn, %{"id" => id}) do
    case Cluster.get_node(id) do
      nil ->
        json_not_found(conn, "Node")

      node ->
        json_response(conn, node_to_json(node))
    end
  end

  @doc """
  Create a new node.

  POST /api/v1/nodes
  """
  def create(conn, %{"node" => node_params}) do
    case Cluster.create_node(node_params) do
      {:ok, node} ->
        json_created(conn, node_to_json(node))

      {:error, changeset} ->
        json_validation_error(conn, changeset)
    end
  end

  def create(conn, params) do
    # Handle case where params aren't nested under "node"
    create(conn, %{"node" => params})
  end

  @doc """
  Update an existing node.

  PATCH/PUT /api/v1/nodes/:id
  """
  def update(conn, %{"id" => id, "node" => node_params}) do
    case Cluster.get_node(id) do
      nil ->
        json_not_found(conn, "Node")

      node ->
        case Cluster.update_node(node, node_params) do
          {:ok, updated_node} ->
            json_response(conn, node_to_json(updated_node))

          {:error, changeset} ->
            json_validation_error(conn, changeset)
        end
    end
  end

  def update(conn, %{"id" => id} = params) do
    # Handle case where params aren't nested under "node"
    node_params = Map.drop(params, ["id"])
    update(conn, %{"id" => id, "node" => node_params})
  end

  @doc """
  Delete a node.

  DELETE /api/v1/nodes/:id
  """
  def delete(conn, %{"id" => id}) do
    case Cluster.get_node(id) do
      nil ->
        json_not_found(conn, "Node")

      node ->
        case Cluster.delete_node(node) do
          {:ok, _} ->
            json_no_content(conn)

          {:error, changeset} ->
            json_validation_error(conn, changeset)
        end
    end
  end

  @doc """
  Test connection to a node.

  POST /api/v1/nodes/:id/test
  """
  def test(conn, %{"id" => id}) do
    case Cluster.get_node(id) do
      nil ->
        json_not_found(conn, "Node")

      node ->
        case Cluster.test_connection(node) do
          {:ok, message} ->
            json_response(conn, %{
              node_id: node.id,
              name: node.name,
              status: "connected",
              message: message
            })

          {:error, message} ->
            conn
            |> put_status(:service_unavailable)
            |> json(%{
              data: %{
                node_id: node.id,
                name: node.name,
                status: "failed",
                message: message
              }
            })
        end
    end
  end

  # Private helpers

  defp node_to_json(node) do
    %{
      id: node.id,
      name: node.name,
      host: node.host,
      port: node.port,
      status: node.status,
      last_seen_at: node.last_seen_at,
      inserted_at: node.inserted_at,
      updated_at: node.updated_at
    }
  end
end
