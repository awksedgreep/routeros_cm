defmodule RouterosCm.MikroTik.Client do
  @moduledoc """
  Wrapper around MikrotikApi library for RouterosCm.

  Handles auth creation from Node records and provides convenience functions
  for tunnel management operations.
  """

  alias RouterosCm.Cluster.Node
  require Logger

  @doc """
  Creates MikrotikApi.Auth from a Node struct.
  """
  def auth_from_node(%Node{} = node) do
    MikrotikApi.Auth.new(
      username: Node.get_username(node),
      password: Node.get_password(node),
      verify: :verify_none
    )
  end

  @doc """
  Tests connection to a MikroTik node.
  Returns `{:ok, system_info}` or `{:error, reason}`.
  """
  def test_connection(%Node{} = node) do
    auth = auth_from_node(node)
    opts = get_opts(node)

    with {:ok, resource} <- MikrotikApi.system_resource(auth, node.host, opts),
         {:ok, identity} <- MikrotikApi.system_identity(auth, node.host, opts) do
      {:ok,
       %{
         identity: identity["name"],
         version: resource["version"],
         uptime: resource["uptime"],
         cpu_load: resource["cpu-load"]
       }}
    end
  end

  # WireGuard Interface Operations

  @doc """
  Lists all WireGuard interfaces on a node.
  """
  def list_wireguard_interfaces(%Node{} = node) do
    MikrotikApi.wireguard_interface_list(auth_from_node(node), node.host, get_opts(node))
  end

  @doc """
  Creates a WireGuard interface.
  """
  def create_wireguard_interface(%Node{} = node, attrs) do
    MikrotikApi.wireguard_interface_add(auth_from_node(node), node.host, attrs, get_opts(node))
  end

  @doc """
  Updates a WireGuard interface.
  """
  def update_wireguard_interface(%Node{} = node, id, attrs) do
    MikrotikApi.wireguard_interface_update(
      auth_from_node(node),
      node.host,
      id,
      attrs,
      get_opts(node)
    )
  end

  @doc """
  Deletes a WireGuard interface.
  """
  def delete_wireguard_interface(%Node{} = node, id) do
    MikrotikApi.wireguard_interface_delete(auth_from_node(node), node.host, id, get_opts(node))
  end

  # WireGuard Peer Operations

  @doc """
  Lists WireGuard peers for an interface.
  """
  def list_wireguard_peers(%Node{} = node, interface_name) do
    opts = Keyword.put(get_opts(node), :params, %{interface: interface_name})

    MikrotikApi.wireguard_peer_list(auth_from_node(node), node.host, opts)
  end

  @doc """
  Creates a WireGuard peer for a specific interface.
  """
  def create_wireguard_peer(%Node{} = node, interface_name, attrs) do
    attrs_with_interface = Map.put(attrs, "interface", interface_name)

    MikrotikApi.wireguard_peer_add(
      auth_from_node(node),
      node.host,
      attrs_with_interface,
      get_opts(node)
    )
  end

  @doc """
  Updates a WireGuard peer.
  """
  def update_wireguard_peer(%Node{} = node, id, attrs) do
    MikrotikApi.wireguard_peer_update(auth_from_node(node), node.host, id, attrs, get_opts(node))
  end

  @doc """
  Deletes a WireGuard peer by interface name and public key.
  """
  def delete_wireguard_peer(%Node{} = node, interface_name, public_key) do
    case list_wireguard_peers(node, interface_name) do
      {:ok, peers} ->
        peer = Enum.find(peers, fn p -> p["public-key"] == public_key end)

        if peer do
          MikrotikApi.wireguard_peer_delete(
            auth_from_node(node),
            node.host,
            peer[".id"],
            get_opts(node)
          )
        else
          {:error, :not_found}
        end

      error ->
        error
    end
  end

  # GRE Interface Operations

  @doc """
  Lists all GRE interfaces on a node.
  """
  def list_gre_interfaces(%Node{} = node) do
    MikrotikApi.gre_list(auth_from_node(node), node.host, get_opts(node))
  end

  @doc """
  Creates a GRE interface.
  """
  def create_gre_interface(%Node{} = node, attrs) do
    MikrotikApi.gre_add(auth_from_node(node), node.host, attrs, get_opts(node))
  end

  @doc """
  Updates a GRE interface.
  """
  def update_gre_interface(%Node{} = node, id, attrs) do
    MikrotikApi.gre_update(auth_from_node(node), node.host, id, attrs, get_opts(node))
  end

  @doc """
  Deletes a GRE interface.
  """
  def delete_gre_interface(%Node{} = node, id) do
    MikrotikApi.gre_delete(auth_from_node(node), node.host, id, get_opts(node))
  end

  # IP Address Operations

  @doc """
  Lists IP addresses, optionally filtered by interface.
  """
  def list_addresses(%Node{} = node, interface \\ nil) do
    opts =
      if interface do
        Keyword.put(get_opts(node), :params, %{interface: interface})
      else
        get_opts(node)
      end

    MikrotikApi.ip_address_list(auth_from_node(node), node.host, opts)
  end

  @doc """
  Assigns an IP address to an interface.
  """
  def create_address(%Node{} = node, attrs) do
    MikrotikApi.ip_address_add(auth_from_node(node), node.host, attrs, get_opts(node))
  end

  @doc """
  Ensures an IP address exists with the given attributes.
  """
  def ensure_address(%Node{} = node, attrs) do
    MikrotikApi.ip_address_ensure(auth_from_node(node), node.host, attrs, get_opts(node))
  end

  @doc """
  Removes an IP address.
  """
  def delete_address(%Node{} = node, id) do
    MikrotikApi.ip_address_delete(auth_from_node(node), node.host, id, get_opts(node))
  end

  # DNS Operations

  @doc """
  Lists all static DNS records on a node.
  """
  def list_dns_records(%Node{} = node) do
    MikrotikApi.dns_static_list(auth_from_node(node), node.host, get_opts(node))
  end

  @doc """
  Creates a static DNS record.
  """
  def create_dns_record(%Node{} = node, attrs) do
    MikrotikApi.dns_static_add(auth_from_node(node), node.host, attrs, get_opts(node))
  end

  @doc """
  Updates a DNS record.
  """
  def update_dns_record(%Node{} = node, id, attrs) do
    MikrotikApi.dns_static_update(auth_from_node(node), node.host, id, attrs, get_opts(node))
  end

  @doc """
  Deletes a DNS record.
  """
  def delete_dns_record(%Node{} = node, id) do
    MikrotikApi.dns_static_delete(auth_from_node(node), node.host, id, get_opts(node))
  end

  @doc """
  Gets DNS server settings.
  """
  def get_dns_settings(%Node{} = node) do
    MikrotikApi.dns_settings_get(auth_from_node(node), node.host, get_opts(node))
  end

  @doc """
  Updates DNS server settings.
  """
  def update_dns_settings(%Node{} = node, attrs) do
    MikrotikApi.dns_settings_set(auth_from_node(node), node.host, attrs, get_opts(node))
  end

  @doc """
  Lists DNS cache entries.
  """
  def list_dns_cache(%Node{} = node) do
    MikrotikApi.dns_cache_list(auth_from_node(node), node.host, get_opts(node))
  end

  @doc """
  Flushes DNS cache.
  """
  def flush_dns_cache(%Node{} = node) do
    MikrotikApi.dns_cache_flush(auth_from_node(node), node.host, get_opts(node))
  end

  # RouterOS User Management Operations

  @doc """
  Lists all RouterOS users on a node.
  """
  def list_routeros_users(%Node{} = node) do
    MikrotikApi.user_list(auth_from_node(node), node.host, get_opts(node))
  end

  @doc """
  Creates a new RouterOS user.

  Params:
  - name: Username (required)
  - password: Password (required)
  - group: User group (default: "full", options: "full", "write", "read")
  - comment: Optional comment
  """
  def create_routeros_user(%Node{} = node, params) do
    MikrotikApi.user_add(auth_from_node(node), node.host, params, get_opts(node))
  end

  @doc """
  Updates an existing RouterOS user.
  """
  def update_routeros_user(%Node{} = node, user_id, params) do
    MikrotikApi.user_update(auth_from_node(node), node.host, user_id, params, get_opts(node))
  end

  @doc """
  Deletes a RouterOS user.
  """
  def delete_routeros_user(%Node{} = node, user_id) do
    MikrotikApi.user_delete(auth_from_node(node), node.host, user_id, get_opts(node))
  end

  @doc """
  Lists all RouterOS user groups.
  """
  def list_user_groups(%Node{} = node) do
    MikrotikApi.user_group_list(auth_from_node(node), node.host, get_opts(node))
  end

  @doc """
  Lists currently active RouterOS users/sessions.
  """
  def list_active_users(%Node{} = node) do
    MikrotikApi.user_active_list(auth_from_node(node), node.host, get_opts(node))
  end

  # System Resource Operations

  @doc """
  Gets system resource information from a node.
  Returns CPU load, memory usage, uptime, version, board info, etc.
  """
  def get_system_resources(%Node{} = node) do
    MikrotikApi.system_resource(auth_from_node(node), node.host, get_opts(node))
  end

  @doc """
  Gets system identity (hostname) from a node.
  """
  def get_system_identity(%Node{} = node) do
    MikrotikApi.system_identity(auth_from_node(node), node.host, get_opts(node))
  end

  @doc """
  Returns connection options (scheme, port) for API calls based on node configuration.
  """
  def get_opts(%Node{port: port}) do
    # Determine scheme based on port (REST API uses HTTP/HTTPS on 80/443)
    scheme =
      case port do
        80 -> :http
        443 -> :https
        _ -> :http
      end

    [scheme: scheme, port: port]
  end
end
