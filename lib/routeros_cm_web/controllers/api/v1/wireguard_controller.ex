defmodule RouterosCmWeb.API.V1.WireGuardController do
  @moduledoc """
  API controller for managing WireGuard interfaces and peers across the cluster.
  """
  use RouterosCmWeb, :controller

  import RouterosCmWeb.API.V1.Base

  alias RouterosCm.Tunnels
  alias RouterosCm.WireGuard.Keys

  plug :require_scope, "wireguard:read" when action in [:index, :show, :list_peers]
  plug :require_scope, "wireguard:write" when action in [:create, :delete, :assign_ip, :remove_ip, :create_peer, :delete_peer, :generate_keypair]

  @doc """
  List all WireGuard interfaces across the cluster (grouped by name).

  GET /api/v1/wireguard
  """
  def index(conn, _params) do
    results = Tunnels.list_wireguard_interfaces(current_scope(conn))
    interfaces = group_interfaces_by_name(results)

    json_response(conn, Enum.map(interfaces, &interface_to_json/1))
  end

  @doc """
  Get a specific WireGuard interface by name.

  GET /api/v1/wireguard/:name
  """
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

  @doc """
  Create a new WireGuard interface across the cluster.

  POST /api/v1/wireguard
  Body:
    - name: Interface name (required)
    - listen-port: UDP listen port (optional)
    - mtu: MTU value (optional)
    - private-key: Private key (optional, auto-generated if not provided)
  """
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

  @doc """
  Delete a WireGuard interface by name from all nodes.

  DELETE /api/v1/wireguard/:name
  """
  def delete(conn, %{"name" => name}) do
    case Tunnels.delete_wireguard_interface_cluster(current_scope(conn), name) do
      {:ok, successes} ->
        json_cluster_result(conn, "delete", "wireguard_interface", successes, [])

      {:error, %{failures: failures}} ->
        json_cluster_result(conn, "delete", "wireguard_interface", [], failures)
    end
  end

  @doc """
  Assign an IP address to a WireGuard interface.

  POST /api/v1/wireguard/:name/ip
  Body:
    - address: IP address with prefix (e.g., "10.0.0.1/24")
  """
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

  @doc """
  Remove an IP address from a WireGuard interface.

  DELETE /api/v1/wireguard/:name/ip/:address
  """
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

  @doc """
  List peers for a WireGuard interface.

  GET /api/v1/wireguard/:name/peers
  """
  def list_peers(conn, %{"name" => name}) do
    case Tunnels.list_wireguard_peers(current_scope(conn), name) do
      {:ok, results} ->
        peers = group_peers_by_key(results, name)
        json_response(conn, Enum.map(peers, &peer_to_json/1))

      {:error, _failures} ->
        json_response(conn, [])
    end
  end

  @doc """
  Create a WireGuard peer on an interface.

  POST /api/v1/wireguard/:name/peers
  Body:
    - public-key: Peer's public key (required)
    - allowed-address: Allowed IP address/subnet (required)
    - endpoint-address: Peer's endpoint address (optional)
    - endpoint-port: Peer's endpoint port (optional)
    - persistent-keepalive: Keepalive interval (optional)
  """
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

  @doc """
  Delete a WireGuard peer from an interface.

  DELETE /api/v1/wireguard/:name/peers/:public_key
  """
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

  @doc """
  Generate a new WireGuard keypair.

  POST /api/v1/wireguard/generate-keypair

  Returns a new private and public key pair. The private key can be used
  when creating a WireGuard interface, and the public key can be shared
  with peers.
  """
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
