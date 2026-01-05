defmodule RouterosCmWeb.API.V1.GREController do
  @moduledoc """
  API controller for managing GRE tunnel interfaces across the cluster.
  """
  use RouterosCmWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import RouterosCmWeb.API.V1.Base

  alias RouterosCm.Tunnels
  alias OpenApiSpex.Schema
  alias RouterosCmWeb.ApiSchemas

  plug :require_scope, "tunnels:read" when action in [:index, :show]
  plug :require_scope, "tunnels:write" when action in [:create, :delete, :assign_ip, :remove_ip]

  tags ["GRE Tunnels"]
  security [%{"bearer" => []}]

  operation :index,
    summary: "List GRE interfaces",
    description: "Returns all GRE tunnel interfaces across the cluster, grouped by name.",
    responses: [
      ok: {"GRE interface list", "application/json", %Schema{
        type: :object,
        properties: %{data: %Schema{type: :array, items: ApiSchemas.GREInterface}}
      }},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]

  def index(conn, _params) do
    results = Tunnels.list_gre_interfaces(current_scope(conn))
    interfaces = group_interfaces_by_name(results)

    json_response(conn, Enum.map(interfaces, &interface_to_json/1))
  end

  operation :show,
    summary: "Get a GRE interface",
    description: "Returns a specific GRE interface by name.",
    parameters: [
      name: [in: :path, type: :string, description: "Interface name", required: true]
    ],
    responses: [
      ok: {"GRE interface", "application/json", %Schema{
        type: :object,
        properties: %{data: ApiSchemas.GREInterface}
      }},
      not_found: {"Not found", "application/json", ApiSchemas.Error},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]

  def show(conn, %{"name" => name}) do
    results = Tunnels.list_gre_interfaces(current_scope(conn))
    interfaces = group_interfaces_by_name(results)

    case Enum.find(interfaces, &(&1.name == name)) do
      nil ->
        json_not_found(conn, "GRE interface")

      interface ->
        json_response(conn, interface_to_json(interface))
    end
  end

  operation :create,
    summary: "Create a GRE interface",
    description: "Creates a new GRE tunnel interface across all nodes.",
    request_body: {"GRE interface parameters", "application/json", %Schema{
      type: :object,
      required: [:name, "local-address", "remote-address"],
      properties: %{
        name: %Schema{type: :string, description: "Interface name"},
        "local-address": %Schema{type: :string, description: "Local endpoint IP"},
        "remote-address": %Schema{type: :string, description: "Remote endpoint IP"},
        mtu: %Schema{type: :string, description: "MTU value"},
        "ipsec-secret": %Schema{type: :string, description: "IPSec shared secret"}
      }
    }},
    responses: [
      ok: {"Creation result", "application/json", ApiSchemas.ClusterResult},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]

  def create(conn, params) do
    attrs = normalize_gre_params(params)

    case Tunnels.create_gre_interface(current_scope(conn), attrs) do
      {:ok, successes} ->
        json_cluster_result(conn, "create", "gre_interface", successes, [])

      {:error, %{successes: successes, failures: failures}} ->
        json_cluster_result(conn, "create", "gre_interface", successes, failures)
    end
  end

  operation :delete,
    summary: "Delete a GRE interface",
    description: "Deletes a GRE interface by name from all nodes.",
    parameters: [
      name: [in: :path, type: :string, description: "Interface name", required: true]
    ],
    responses: [
      ok: {"Delete result", "application/json", ApiSchemas.ClusterResult},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]

  def delete(conn, %{"name" => name}) do
    case Tunnels.delete_gre_interface_by_name(current_scope(conn), name) do
      {:ok, successes, []} ->
        json_cluster_result(conn, "delete", "gre_interface", successes, [])

      {:ok, successes, failures} ->
        json_cluster_result(conn, "delete", "gre_interface", successes, failures)
    end
  end

  operation :assign_ip,
    summary: "Assign IP to GRE interface",
    description: "Assigns an IP address to a GRE interface across all nodes.",
    parameters: [
      name: [in: :path, type: :string, description: "Interface name", required: true]
    ],
    request_body: {"IP address", "application/json", %Schema{
      type: :object,
      required: [:address],
      properties: %{
        address: %Schema{type: :string, description: "IP address with prefix (e.g., 172.16.0.1/30)"}
      }
    }},
    responses: [
      ok: {"Assignment result", "application/json", ApiSchemas.ClusterResult},
      bad_request: {"Bad request", "application/json", ApiSchemas.Error},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]

  def assign_ip(conn, %{"name" => name} = params) do
    address = params["address"]

    if is_nil(address) or address == "" do
      json_bad_request(conn, "address is required")
    else
      case Tunnels.assign_gre_ip(current_scope(conn), name, address) do
        {:ok, successes} ->
          json_cluster_result(conn, "assign_ip", "gre_interface", successes, [])

        {:error, %{failures: failures}} ->
          json_cluster_result(conn, "assign_ip", "gre_interface", [], failures)
      end
    end
  end

  operation :remove_ip,
    summary: "Remove IP from GRE interface",
    description: "Removes an IP address from a GRE interface across all nodes.",
    parameters: [
      name: [in: :path, type: :string, description: "Interface name", required: true],
      address: [in: :path, type: :string, description: "IP address to remove (URL-encoded)", required: true]
    ],
    responses: [
      ok: {"Removal result", "application/json", ApiSchemas.ClusterResult},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]

  def remove_ip(conn, %{"name" => name, "address" => address}) do
    # URL-decode the address since it may contain / character
    decoded_address = URI.decode(address)

    case Tunnels.remove_gre_ip(current_scope(conn), name, decoded_address) do
      {:ok, successes} ->
        json_cluster_result(conn, "remove_ip", "gre_interface", successes, [])

      {:error, %{failures: failures}} ->
        json_cluster_result(conn, "remove_ip", "gre_interface", [], failures)
    end
  end

  # Private helpers

  defp normalize_gre_params(params) do
    params
    |> Map.take(["name", "local-address", "remote-address", "mtu", "ipsec-secret", "allow-fast-path", "comment"])
    |> Enum.reject(fn {_k, v} -> v == "" or is_nil(v) end)
    |> Map.new()
  end

  defp group_interfaces_by_name(results) do
    results
    |> Enum.flat_map(fn
      {node, {:ok, interfaces}} ->
        Enum.map(interfaces, fn interface ->
          {interface["name"], %{node: node, interface: interface}}
        end)

      {_node, {:error, _reason}} ->
        []
    end)
    |> Enum.group_by(fn {name, _} -> name end, fn {_, data} -> data end)
    |> Enum.map(fn {name, nodes_data} ->
      first = List.first(nodes_data)

      %{
        name: name,
        local_address: first.interface["local-address"],
        remote_address: first.interface["remote-address"],
        mtu: first.interface["mtu"],
        allow_fast_path: first.interface["allow-fast-path"],
        ipsec_secret: if(first.interface["ipsec-secret"], do: "***", else: nil),
        comment: first.interface["comment"],
        disabled: first.interface["disabled"],
        running: first.interface["running"],
        nodes:
          Enum.map(nodes_data, fn data ->
            %{
              node_name: data.node.name,
              node_id: data.node.id,
              interface_id: data.interface[".id"]
            }
          end)
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp interface_to_json(interface) do
    %{
      name: interface.name,
      local_address: interface.local_address,
      remote_address: interface.remote_address,
      mtu: interface.mtu,
      allow_fast_path: interface.allow_fast_path,
      ipsec_secret: interface.ipsec_secret,
      comment: interface.comment,
      disabled: interface.disabled,
      running: interface.running,
      nodes: interface.nodes
    }
  end
end
