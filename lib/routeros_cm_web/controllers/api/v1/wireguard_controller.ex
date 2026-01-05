defmodule RouterosCmWeb.API.V1.WireGuardController do
  @moduledoc """
  API controller for managing WireGuard interfaces and peers across the cluster.
  """
  use RouterosCmWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import RouterosCmWeb.API.V1.Base

  alias RouterosCm.Tunnels
  alias RouterosCm.WireGuard.Keys
  alias OpenApiSpex.Schema
  alias RouterosCmWeb.ApiSchemas

  plug :require_scope, "wireguard:read" when action in [:index, :show, :list_peers]
  plug :require_scope, "wireguard:write" when action in [:create, :delete, :assign_ip, :remove_ip, :create_peer, :delete_peer, :generate_keypair]

  tags ["WireGuard"]
  security [%{"bearer" => []}]

  operation :index,
    summary: "List WireGuard interfaces",
    description: "Returns all WireGuard interfaces across the cluster, grouped by name.",
    responses: [
      ok: {"WireGuard interface list", "application/json", %Schema{
        type: :object,
        properties: %{data: %Schema{type: :array, items: ApiSchemas.WireGuardInterface}}
      }},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]

  def index(conn, _params) do
    results = Tunnels.list_wireguard_interfaces(current_scope(conn))
    interfaces = group_interfaces_by_name(results)

    json_response(conn, Enum.map(interfaces, &interface_to_json/1))
  end

  operation :show,
    summary: "Get a WireGuard interface",
    description: "Returns a specific WireGuard interface by name.",
    parameters: [
      name: [in: :path, type: :string, description: "Interface name", required: true]
    ],
    responses: [
      ok: {"WireGuard interface", "application/json", %Schema{
        type: :object,
        properties: %{data: ApiSchemas.WireGuardInterface}
      }},
      not_found: {"Not found", "application/json", ApiSchemas.Error},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]

  def show(conn, %{"name" => name}) do
    results = Tunnels.list_wireguard_interfaces(current_scope(conn))
    interfaces = group_interfaces_by_name(results)

    case Enum.find(interfaces, &(&1.name == name)) do
      nil ->
        json_not_found(conn, "WireGuard interface")

      interface ->
        json_response(conn, interface_to_json(interface))
    end
  end

  operation :create,
    summary: "Create a WireGuard interface",
    description: "Creates a new WireGuard interface across all nodes.",
    request_body: {"WireGuard interface parameters", "application/json", %Schema{
      type: :object,
      required: [:name],
      properties: %{
        name: %Schema{type: :string, description: "Interface name"},
        "listen-port": %Schema{type: :string, description: "UDP listen port"},
        mtu: %Schema{type: :string, description: "MTU value"},
        "private-key": %Schema{type: :string, description: "Private key (auto-generated if not provided)"}
      }
    }},
    responses: [
      ok: {"Creation result", "application/json", ApiSchemas.ClusterResult},
      bad_request: {"Error", "application/json", ApiSchemas.Error},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]

  def create(conn, params) do
    attrs = normalize_wireguard_params(params)

    case Tunnels.create_wireguard_interface(current_scope(conn), attrs) do
      {:ok, successes} ->
        json_cluster_result(conn, "create", "wireguard_interface", successes, [])

      {:error, :no_nodes} ->
        json_error(conn, "No active nodes available")

      {:error, %{successes: successes, failures: failures}} ->
        json_cluster_result(conn, "create", "wireguard_interface", successes, failures)
    end
  end

  operation :delete,
    summary: "Delete a WireGuard interface",
    description: "Deletes a WireGuard interface by name from all nodes.",
    parameters: [
      name: [in: :path, type: :string, description: "Interface name", required: true]
    ],
    responses: [
      ok: {"Delete result", "application/json", ApiSchemas.ClusterResult},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]

  def delete(conn, %{"name" => name}) do
    case Tunnels.delete_wireguard_interface_cluster(current_scope(conn), name) do
      {:ok, successes} ->
        json_cluster_result(conn, "delete", "wireguard_interface", successes, [])

      {:error, %{failures: failures}} ->
        json_cluster_result(conn, "delete", "wireguard_interface", [], failures)
    end
  end

  operation :assign_ip,
    summary: "Assign IP to WireGuard interface",
    description: "Assigns an IP address to a WireGuard interface across all nodes.",
    parameters: [
      name: [in: :path, type: :string, description: "Interface name", required: true]
    ],
    request_body: {"IP address", "application/json", %Schema{
      type: :object,
      required: [:address],
      properties: %{
        address: %Schema{type: :string, description: "IP address with prefix (e.g., 10.0.0.1/24)"}
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
      case Tunnels.assign_wireguard_ip(current_scope(conn), name, address) do
        {:ok, successes} ->
          json_cluster_result(conn, "assign_ip", "wireguard_interface", successes, [])

        {:error, %{failures: failures}} ->
          json_cluster_result(conn, "assign_ip", "wireguard_interface", [], failures)
      end
    end
  end

  operation :remove_ip,
    summary: "Remove IP from WireGuard interface",
    description: "Removes an IP address from a WireGuard interface across all nodes.",
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

    case Tunnels.remove_wireguard_ip(current_scope(conn), name, decoded_address) do
      {:ok, successes} ->
        json_cluster_result(conn, "remove_ip", "wireguard_interface", successes, [])

      {:error, %{failures: failures}} ->
        json_cluster_result(conn, "remove_ip", "wireguard_interface", [], failures)
    end
  end

  operation :list_peers,
    summary: "List WireGuard peers",
    description: "Returns all peers for a WireGuard interface.",
    parameters: [
      name: [in: :path, type: :string, description: "Interface name", required: true]
    ],
    responses: [
      ok: {"Peer list", "application/json", %Schema{
        type: :object,
        properties: %{data: %Schema{type: :array, items: ApiSchemas.WireGuardPeer}}
      }},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]

  def list_peers(conn, %{"name" => name}) do
    case Tunnels.list_wireguard_peers(current_scope(conn), name) do
      {:ok, results} ->
        peers = group_peers_by_key(results, name)
        json_response(conn, Enum.map(peers, &peer_to_json/1))

      {:error, _failures} ->
        json_response(conn, [])
    end
  end

  operation :create_peer,
    summary: "Create a WireGuard peer",
    description: "Creates a new peer on a WireGuard interface across all nodes.",
    parameters: [
      name: [in: :path, type: :string, description: "Interface name", required: true]
    ],
    request_body: {"Peer parameters", "application/json", %Schema{
      type: :object,
      required: ["public-key", "allowed-address"],
      properties: %{
        "public-key": %Schema{type: :string, description: "Peer's public key"},
        "allowed-address": %Schema{type: :string, description: "Allowed IP address/subnet"},
        "endpoint-address": %Schema{type: :string, description: "Peer's endpoint address"},
        "endpoint-port": %Schema{type: :string, description: "Peer's endpoint port"},
        "persistent-keepalive": %Schema{type: :string, description: "Keepalive interval in seconds"}
      }
    }},
    responses: [
      ok: {"Creation result", "application/json", ApiSchemas.ClusterResult},
      bad_request: {"Bad request", "application/json", ApiSchemas.Error},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]

  def create_peer(conn, %{"name" => name} = params) do
    attrs = normalize_peer_params(params)

    if is_nil(attrs["public-key"]) or attrs["public-key"] == "" do
      json_bad_request(conn, "public-key is required")
    else
      case Tunnels.create_wireguard_peer(current_scope(conn), name, attrs) do
        {:ok, successes} ->
          json_cluster_result(conn, "create", "wireguard_peer", successes, [])

        {:error, :no_nodes} ->
          json_error(conn, "No active nodes available")
      end
    end
  end

  operation :delete_peer,
    summary: "Delete a WireGuard peer",
    description: "Deletes a peer from a WireGuard interface across all nodes.",
    parameters: [
      name: [in: :path, type: :string, description: "Interface name", required: true],
      public_key: [in: :path, type: :string, description: "Peer's public key (URL-encoded)", required: true]
    ],
    responses: [
      ok: {"Delete result", "application/json", ApiSchemas.ClusterResult},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]

  def delete_peer(conn, %{"name" => name, "public_key" => public_key}) do
    # URL-decode the public key since it may contain special characters
    decoded_key = URI.decode(public_key)

    case Tunnels.delete_wireguard_peer_cluster(current_scope(conn), name, decoded_key) do
      {:ok, successes} ->
        json_cluster_result(conn, "delete", "wireguard_peer", successes, [])

      {:error, %{successes: successes, failures: failures}} ->
        json_cluster_result(conn, "delete", "wireguard_peer", successes, failures)
    end
  end

  operation :generate_keypair,
    summary: "Generate WireGuard keypair",
    description: "Generates a new WireGuard private/public key pair.",
    responses: [
      ok: {"Keypair", "application/json", ApiSchemas.WireGuardKeypair},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]

  def generate_keypair(conn, _params) do
    {private_key, public_key} = Keys.generate_key_pair()

    json_response(conn, %{
      private_key: private_key,
      public_key: public_key
    })
  end

  # Private helpers

  defp normalize_wireguard_params(params) do
    params
    |> Map.take(["name", "listen-port", "mtu", "private-key", "comment"])
    |> Enum.reject(fn {_k, v} -> v == "" or is_nil(v) end)
    |> Map.new()
  end

  defp normalize_peer_params(params) do
    params
    |> Map.take(["public-key", "allowed-address", "endpoint-address", "endpoint-port", "persistent-keepalive", "comment"])
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
        listen_port: first.interface["listen-port"],
        mtu: first.interface["mtu"],
        public_key: first.interface["public-key"],
        running: first.interface["running"],
        disabled: first.interface["disabled"],
        comment: first.interface["comment"],
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

  defp group_peers_by_key(results, interface_name) do
    results
    |> Enum.flat_map(fn
      {node, {:ok, peers}} ->
        Enum.map(peers, fn peer ->
          {peer["public-key"], %{node: node, peer: peer}}
        end)

      {_node, {:error, _reason}} ->
        []
    end)
    |> Enum.group_by(fn {key, _} -> key end, fn {_, data} -> data end)
    |> Enum.map(fn {public_key, nodes_data} ->
      first = List.first(nodes_data)

      %{
        public_key: public_key,
        interface: interface_name,
        allowed_address: first.peer["allowed-address"],
        endpoint_address: first.peer["endpoint-address"],
        endpoint_port: first.peer["endpoint-port"],
        persistent_keepalive: first.peer["persistent-keepalive"],
        current_endpoint_address: first.peer["current-endpoint-address"],
        current_endpoint_port: first.peer["current-endpoint-port"],
        last_handshake: first.peer["last-handshake"],
        rx: first.peer["rx"],
        tx: first.peer["tx"],
        disabled: first.peer["disabled"],
        comment: first.peer["comment"],
        nodes:
          Enum.map(nodes_data, fn data ->
            %{
              node_name: data.node.name,
              node_id: data.node.id,
              peer_id: data.peer[".id"]
            }
          end)
      }
    end)
    |> Enum.sort_by(& &1.public_key)
  end

  defp interface_to_json(interface) do
    %{
      name: interface.name,
      listen_port: interface.listen_port,
      mtu: interface.mtu,
      public_key: interface.public_key,
      running: interface.running,
      disabled: interface.disabled,
      comment: interface.comment,
      nodes: interface.nodes
    }
  end

  defp peer_to_json(peer) do
    %{
      public_key: peer.public_key,
      interface: peer.interface,
      allowed_address: peer.allowed_address,
      endpoint_address: peer.endpoint_address,
      endpoint_port: peer.endpoint_port,
      persistent_keepalive: peer.persistent_keepalive,
      current_endpoint_address: peer.current_endpoint_address,
      current_endpoint_port: peer.current_endpoint_port,
      last_handshake: peer.last_handshake,
      rx: peer.rx,
      tx: peer.tx,
      disabled: peer.disabled,
      comment: peer.comment,
      nodes: peer.nodes
    }
  end
end
