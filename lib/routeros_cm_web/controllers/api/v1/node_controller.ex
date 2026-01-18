defmodule RouterosCmWeb.API.V1.NodeController do
  @moduledoc """
  API controller for managing cluster nodes.
  """
  use RouterosCmWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import RouterosCmWeb.API.V1.Base

  alias RouterosCm.Cluster
  alias OpenApiSpex.Schema
  alias RouterosCmWeb.ApiSchemas

  plug :require_scope, "nodes:read" when action in [:index, :show]
  plug :require_scope, "nodes:write" when action in [:create, :update, :delete, :test]

  tags(["Nodes"])
  security([%{"bearer" => []}])

  operation(:index,
    summary: "List all nodes",
    description: "Returns a list of all nodes in the cluster.",
    responses: [
      ok:
        {"Node list", "application/json",
         %Schema{
           type: :object,
           properties: %{data: %Schema{type: :array, items: ApiSchemas.Node}}
         }},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]
  )

  def index(conn, _params) do
    nodes = Cluster.list_nodes()
    json_response(conn, Enum.map(nodes, &node_to_json/1))
  end

  operation(:show,
    summary: "Get a node",
    description: "Returns a specific node by ID.",
    parameters: [
      id: [in: :path, type: :integer, description: "Node ID", required: true]
    ],
    responses: [
      ok:
        {"Node details", "application/json",
         %Schema{
           type: :object,
           properties: %{data: ApiSchemas.Node}
         }},
      not_found: {"Not found", "application/json", ApiSchemas.Error},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]
  )

  def show(conn, %{"id" => id}) do
    case Cluster.get_node(id) do
      nil ->
        json_not_found(conn, "Node")

      node ->
        json_response(conn, node_to_json(node))
    end
  end

  operation(:create,
    summary: "Create a node",
    description: "Creates a new node in the cluster.",
    request_body: {"Node parameters", "application/json", ApiSchemas.NodeCreateRequest},
    responses: [
      created:
        {"Node created", "application/json",
         %Schema{
           type: :object,
           properties: %{data: ApiSchemas.Node}
         }},
      unprocessable_entity: {"Validation error", "application/json", ApiSchemas.Error},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]
  )

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

  operation(:update,
    summary: "Update a node",
    description: "Updates an existing node.",
    parameters: [
      id: [in: :path, type: :integer, description: "Node ID", required: true]
    ],
    request_body: {"Node parameters", "application/json", ApiSchemas.NodeCreateRequest},
    responses: [
      ok:
        {"Node updated", "application/json",
         %Schema{
           type: :object,
           properties: %{data: ApiSchemas.Node}
         }},
      not_found: {"Not found", "application/json", ApiSchemas.Error},
      unprocessable_entity: {"Validation error", "application/json", ApiSchemas.Error},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]
  )

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

  operation(:delete,
    summary: "Delete a node",
    description: "Removes a node from the cluster.",
    parameters: [
      id: [in: :path, type: :integer, description: "Node ID", required: true]
    ],
    responses: [
      no_content: "Node deleted",
      not_found: {"Not found", "application/json", ApiSchemas.Error},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]
  )

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

  operation(:test,
    summary: "Test node connection",
    description: "Tests the connection to a specific node.",
    parameters: [
      id: [in: :path, type: :integer, description: "Node ID", required: true]
    ],
    responses: [
      ok:
        {"Connection successful", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{
               type: :object,
               properties: %{
                 node_id: %Schema{type: :integer},
                 name: %Schema{type: :string},
                 status: %Schema{type: :string},
                 message: %Schema{type: :string}
               }
             }
           }
         }},
      service_unavailable:
        {"Connection failed", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{
               type: :object,
               properties: %{
                 node_id: %Schema{type: :integer},
                 name: %Schema{type: :string},
                 status: %Schema{type: :string},
                 message: %Schema{type: :string}
               }
             }
           }
         }},
      not_found: {"Not found", "application/json", ApiSchemas.Error},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]
  )

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
