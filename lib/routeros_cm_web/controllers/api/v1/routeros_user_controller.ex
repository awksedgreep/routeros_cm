defmodule RouterosCmWeb.API.V1.RouterOSUserController do
  @moduledoc """
  API controller for managing RouterOS users across the cluster.
  """
  use RouterosCmWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import RouterosCmWeb.API.V1.Base

  alias RouterosCm.RouterOSUsers
  alias OpenApiSpex.Schema
  alias RouterosCmWeb.ApiSchemas

  plug :require_scope, "users:read" when action in [:index, :show, :groups, :active_sessions]
  plug :require_scope, "users:write" when action in [:create, :update, :delete]

  tags(["RouterOS Users"])
  security([%{"bearer" => []}])

  operation(:index,
    summary: "List RouterOS users",
    description: "Returns all RouterOS users across the cluster, grouped by name.",
    responses: [
      ok:
        {"User list", "application/json",
         %Schema{
           type: :object,
           properties: %{data: %Schema{type: :array, items: ApiSchemas.RouterOSUser}}
         }},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]
  )

  def index(conn, _params) do
    {:ok, results} = RouterOSUsers.list_routeros_users(current_scope: current_scope(conn))
    users = group_users_by_name(results)

    json_response(conn, Enum.map(users, &user_to_json/1))
  end

  operation(:show,
    summary: "Get a RouterOS user",
    description: "Returns a specific RouterOS user by name.",
    parameters: [
      name: [in: :path, type: :string, description: "Username", required: true]
    ],
    responses: [
      ok:
        {"User details", "application/json",
         %Schema{
           type: :object,
           properties: %{data: ApiSchemas.RouterOSUser}
         }},
      not_found: {"Not found", "application/json", ApiSchemas.Error},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]
  )

  def show(conn, %{"name" => name}) do
    {:ok, results} = RouterOSUsers.list_routeros_users(current_scope: current_scope(conn))
    users = group_users_by_name(results)

    case Enum.find(users, &(&1.name == name)) do
      nil ->
        json_not_found(conn, "RouterOS user")

      user ->
        json_response(conn, user_to_json(user))
    end
  end

  operation(:create,
    summary: "Create a RouterOS user",
    description: "Creates a new RouterOS user across all nodes.",
    request_body: {"User parameters", "application/json", ApiSchemas.RouterOSUserCreateRequest},
    responses: [
      ok: {"Creation result", "application/json", ApiSchemas.ClusterResult},
      bad_request: {"Bad request", "application/json", ApiSchemas.Error},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]
  )

  def create(conn, params) do
    attrs = normalize_user_params(params)

    if is_nil(attrs["name"]) or attrs["name"] == "" do
      json_bad_request(conn, "name is required")
    else
      if is_nil(attrs["password"]) or attrs["password"] == "" do
        json_bad_request(conn, "password is required")
      else
        {:ok, successes, failures} =
          RouterOSUsers.create_routeros_user(attrs, "all", current_scope(conn))

        json_cluster_result(
          conn,
          "create",
          "routeros_user",
          format_successes(successes),
          failures
        )
      end
    end
  end

  operation(:update,
    summary: "Update a RouterOS user",
    description: "Updates a RouterOS user by name across all nodes.",
    parameters: [
      name: [in: :path, type: :string, description: "Username", required: true]
    ],
    request_body:
      {"User parameters", "application/json",
       %Schema{
         type: :object,
         properties: %{
           group: %Schema{type: :string, description: "User group"},
           password: %Schema{type: :string, description: "New password"},
           comment: %Schema{type: :string, description: "Comment"}
         }
       }},
    responses: [
      ok: {"Update result", "application/json", ApiSchemas.ClusterResult},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]
  )

  def update(conn, %{"name" => name} = params) do
    attrs =
      params
      |> Map.drop(["name"])
      |> normalize_user_params()

    {:ok, successes, failures} =
      RouterOSUsers.update_routeros_user_by_name(name, attrs, current_scope(conn))

    json_cluster_result(conn, "update", "routeros_user", successes, failures)
  end

  operation(:delete,
    summary: "Delete a RouterOS user",
    description: "Deletes a RouterOS user by name from all nodes.",
    parameters: [
      name: [in: :path, type: :string, description: "Username", required: true]
    ],
    responses: [
      ok: {"Delete result", "application/json", ApiSchemas.ClusterResult},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]
  )

  def delete(conn, %{"name" => name}) do
    {:ok, successes, failures} =
      RouterOSUsers.delete_routeros_user_by_name(name, current_scope(conn))

    json_cluster_result(conn, "delete", "routeros_user", successes, failures)
  end

  operation(:groups,
    summary: "List user groups",
    description: "Returns all unique user groups across the cluster.",
    responses: [
      ok:
        {"Group list", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   name: %Schema{type: :string},
                   policy: %Schema{type: :string},
                   skin: %Schema{type: :string}
                 }
               }
             }
           }
         }},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]
  )

  def groups(conn, _params) do
    {:ok, results} = RouterOSUsers.list_user_groups()
    groups = collect_unique_groups(results)

    json_response(conn, groups)
  end

  operation(:active_sessions,
    summary: "List active sessions",
    description: "Returns all active user sessions across the cluster.",
    responses: [
      ok:
        {"Session list", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   node_name: %Schema{type: :string},
                   node_id: %Schema{type: :integer},
                   name: %Schema{type: :string},
                   address: %Schema{type: :string},
                   via: %Schema{type: :string},
                   when: %Schema{type: :string},
                   group: %Schema{type: :string}
                 }
               }
             }
           }
         }},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]
  )

  def active_sessions(conn, _params) do
    {:ok, results} = RouterOSUsers.list_active_users()
    sessions = format_active_sessions(results)

    json_response(conn, sessions)
  end

  # Private helpers

  defp normalize_user_params(params) do
    params
    |> Map.take(["name", "password", "group", "comment"])
    |> Enum.reject(fn {_k, v} -> v == "" or is_nil(v) end)
    |> Map.new()
  end

  defp group_users_by_name(results) do
    results
    |> Enum.flat_map(fn
      {node, {:ok, users}} ->
        Enum.map(users, fn user ->
          {user["name"], %{node: node, user: user}}
        end)

      {_node, {:error, _reason}} ->
        []

      {:error, _reason} ->
        []
    end)
    |> Enum.group_by(fn {name, _} -> name end, fn {_, data} -> data end)
    |> Enum.map(fn {name, nodes_data} ->
      first = List.first(nodes_data)

      %{
        name: name,
        group: first.user["group"],
        comment: first.user["comment"],
        disabled: first.user["disabled"],
        last_logged_in: first.user["last-logged-in"],
        nodes:
          Enum.map(nodes_data, fn data ->
            %{
              node_name: data.node.name,
              node_id: data.node.id,
              user_id: data.user[".id"],
              disabled: data.user["disabled"],
              last_logged_in: data.user["last-logged-in"]
            }
          end)
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp user_to_json(user) do
    %{
      name: user.name,
      group: user.group,
      comment: user.comment,
      disabled: user.disabled,
      last_logged_in: user.last_logged_in,
      nodes: user.nodes
    }
  end

  defp format_successes(successes) do
    Enum.map(successes, fn
      {:ok, node} -> {node, {:ok, nil}}
      other -> other
    end)
  end

  defp collect_unique_groups(results) do
    results
    |> Enum.flat_map(fn
      {_node, {:ok, groups}} -> groups
      {_node, {:error, _}} -> []
      {:error, _} -> []
    end)
    |> Enum.uniq_by(& &1["name"])
    |> Enum.map(fn group ->
      %{
        name: group["name"],
        policy: group["policy"],
        skin: group["skin"]
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp format_active_sessions(results) do
    results
    |> Enum.flat_map(fn
      {node, {:ok, sessions}} ->
        Enum.map(sessions, fn session ->
          %{
            node_name: node.name,
            node_id: node.id,
            name: session["name"],
            address: session["address"],
            via: session["via"],
            when: session["when"],
            group: session["group"]
          }
        end)

      {_node, {:error, _}} ->
        []

      {:error, _} ->
        []
    end)
    |> Enum.sort_by(& &1.name)
  end
end
