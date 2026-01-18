defmodule RouterosCm.Tunnels do
  @moduledoc """
  The Tunnels context - business logic for managing WireGuard and GRE tunnels.

  Uses MikrotikApi cluster helpers for operations that need to be synchronized
  across multiple nodes (e.g., WireGuard with shared private keys).
  """

  alias RouterosCm.{Audit, Cluster}
  alias RouterosCm.MikroTik.Client
  require Logger

  # WireGuard Interface Management

  @doc """
  Lists all WireGuard interfaces across all active nodes.

  Returns a list of tuples: `{node, interfaces}` where interfaces is either
  `{:ok, list}` or `{:error, reason}`.
  """
  def list_wireguard_interfaces(_current_scope) do
    Cluster.list_active_nodes()
    |> Task.async_stream(
      fn node ->
        {node, Client.list_wireguard_interfaces(node)}
      end,
      timeout: 10_000,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, :timeout} -> {nil, {:error, :timeout}}
    end)
    |> Enum.reject(fn {node, _} -> is_nil(node) end)
  end

  @doc """
  Gets WireGuard interfaces from a specific node.
  """
  def list_wireguard_interfaces_for_node(node) do
    Client.list_wireguard_interfaces(node)
  end

  @doc """
  Creates a WireGuard interface on specified nodes using the MikrotikApi cluster helper.

  This ensures the same private key is deployed to all nodes, enabling cluster failover.

  ## Options
  - `:nodes` - list of node IDs to create interface on. If omitted, creates on all active nodes.
  - `:cluster_wide` - boolean, if true creates on all active nodes (overrides :nodes)
  """
  def create_wireguard_interface(current_scope, attrs, opts \\ []) do
    nodes = get_target_nodes(current_scope, opts)

    case nodes do
      [] ->
        {:error, :no_nodes}

      [primary | _rest] = all_nodes ->
        auth = Client.auth_from_node(primary)
        ips = Enum.map(all_nodes, & &1.host)
        name = attrs["name"]
        api_opts = Client.get_opts(primary)

        case MikrotikApi.wireguard_cluster_add(auth, ips, name, attrs, api_opts) do
          {:ok, results} ->
            # Map IPs back to nodes for response
            successes = map_results_to_nodes(results, all_nodes)

            Audit.log_wireguard_action("create", name, %{
              user_id: current_scope.user.id,
              details: %{attrs: attrs, nodes: Enum.map(all_nodes, & &1.id)}
            })

            {:ok, successes}

          {:error, reason} ->
            Logger.error("Failed to create WireGuard interface cluster-wide: #{inspect(reason)}")
            {:error, %{successes: [], failures: [{primary, reason}]}}
        end
    end
  end

  @doc """
  Updates a WireGuard interface on specified nodes.
  """
  def update_wireguard_interface(current_scope, interface_id, attrs, opts \\ []) do
    nodes = get_target_nodes(current_scope, opts)

    results =
      Task.async_stream(
        nodes,
        fn node ->
          {node, Client.update_wireguard_interface(node, interface_id, attrs)}
        end,
        timeout: 15_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, :timeout} -> {nil, {:error, :timeout}}
      end)

    case Enum.split_with(results, fn {_node, result} -> match?({:ok, _}, result) end) do
      {successes, []} ->
        Audit.log_wireguard_action("update", interface_id, %{
          user_id: current_scope.user.id,
          details: %{attrs: attrs, nodes: Enum.map(nodes, & &1.id)}
        })

        {:ok, successes}

      {successes, failures} ->
        Audit.log_failure("update", "wireguard_interface", "partial_failure", %{
          user_id: current_scope.user.id,
          resource_id: interface_id,
          details: %{attrs: attrs, successes: length(successes), failures: length(failures)}
        })

        {:error, %{successes: successes, failures: failures}}
    end
  end

  @doc """
  Deletes a WireGuard interface from specified nodes.
  """
  def delete_wireguard_interface(current_scope, interface_id, opts \\ []) do
    nodes = get_target_nodes(current_scope, opts)

    results =
      Task.async_stream(
        nodes,
        fn node ->
          {node, Client.delete_wireguard_interface(node, interface_id)}
        end,
        timeout: 15_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, :timeout} -> {nil, {:error, :timeout}}
      end)

    case Enum.split_with(results, fn {_node, result} -> match?({:ok, _}, result) end) do
      {successes, []} ->
        Audit.log_wireguard_action("delete", interface_id, %{
          user_id: current_scope.user.id,
          details: %{nodes: Enum.map(nodes, & &1.id)}
        })

        {:ok, successes}

      {successes, failures} ->
        Audit.log_failure("delete", "wireguard_interface", "partial_failure", %{
          user_id: current_scope.user.id,
          resource_id: interface_id,
          details: %{successes: length(successes), failures: length(failures)}
        })

        {:error, %{successes: successes, failures: failures}}
    end
  end

  @doc """
  Deletes a WireGuard interface by name from all active nodes in the cluster.
  """
  def delete_wireguard_interface_cluster(current_scope, interface_name) do
    nodes = Cluster.list_active_nodes()

    # First, find the interface ID on each node (they may differ)
    results =
      Task.async_stream(
        nodes,
        fn node ->
          case Client.list_wireguard_interfaces(node) do
            {:ok, interfaces} ->
              case Enum.find(interfaces, &(&1["name"] == interface_name)) do
                nil ->
                  {node, {:ok, :not_found}}

                interface ->
                  {node, Client.delete_wireguard_interface(node, interface[".id"])}
              end

            error ->
              {node, error}
          end
        end,
        timeout: 15_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, :timeout} -> {nil, {:error, :timeout}}
      end)
      |> Enum.reject(fn {node, _} -> is_nil(node) end)

    case Enum.split_with(results, fn {_node, result} ->
           match?({:ok, _}, result)
         end) do
      {successes, []} ->
        Audit.log_wireguard_action("delete", interface_name, %{
          user_id: current_scope.user.id,
          details: %{cluster_wide: true, nodes: Enum.map(nodes, & &1.id)}
        })

        {:ok, successes}

      {_successes, failures} ->
        {:error, %{failures: failures}}
    end
  end

  @doc """
  Removes an IP address from a WireGuard interface on all active nodes.
  """
  def remove_wireguard_ip(current_scope, interface_name, address) do
    nodes = Cluster.list_active_nodes()

    results =
      Task.async_stream(
        nodes,
        fn node ->
          # Find the address ID on this node
          case Client.list_addresses(node, interface_name) do
            {:ok, addresses} ->
              case Enum.find(addresses, &(&1["address"] == address)) do
                nil ->
                  {node, {:ok, :not_found}}

                addr ->
                  {node, Client.delete_address(node, addr[".id"])}
              end

            error ->
              {node, error}
          end
        end,
        timeout: 15_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, :timeout} -> {nil, {:error, :timeout}}
      end)
      |> Enum.reject(fn {node, _} -> is_nil(node) end)

    case Enum.split_with(results, fn {_node, result} ->
           match?({:ok, _}, result)
         end) do
      {successes, []} ->
        Audit.log_address_action("delete", address, interface_name, %{
          user_id: current_scope.user.id,
          details: %{cluster_wide: true, nodes: Enum.map(nodes, & &1.id)}
        })

        {:ok, successes}

      {_successes, failures} ->
        {:error, %{failures: failures}}
    end
  end

  @doc """
  Assigns an IP address to a WireGuard interface on all active nodes.
  """
  def assign_wireguard_ip(current_scope, interface_name, address) do
    nodes = Cluster.list_active_nodes()

    results =
      Task.async_stream(
        nodes,
        fn node ->
          attrs = %{"address" => address, "interface" => interface_name}
          {node, Client.ensure_address(node, attrs)}
        end,
        timeout: 15_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, :timeout} -> {nil, {:error, :timeout}}
      end)
      |> Enum.reject(fn {node, _} -> is_nil(node) end)

    case Enum.split_with(results, fn {_node, result} ->
           match?({:ok, _}, result)
         end) do
      {successes, []} ->
        Audit.log_wireguard_action("assign_ip", interface_name, %{
          user_id: current_scope.user.id,
          details: %{address: address, nodes: Enum.map(nodes, & &1.id)}
        })

        {:ok, successes}

      {_successes, failures} ->
        {:error, %{failures: failures}}
    end
  end

  # WireGuard Peer Management

  @doc """
  Lists WireGuard peers for a specific interface across all active nodes.
  """
  def list_wireguard_peers(_current_scope, interface_name) do
    Cluster.list_active_nodes()
    |> Task.async_stream(
      fn node ->
        {node, Client.list_wireguard_peers(node, interface_name)}
      end,
      timeout: 10_000,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, :timeout} -> {nil, {:error, :timeout}}
    end)
    |> then(fn results ->
      case Enum.split_with(results, fn {node, result} ->
             not is_nil(node) and match?({:ok, _}, result)
           end) do
        {successes, []} ->
          {:ok, successes}

        {successes, _failures} when successes != [] ->
          {:ok, successes}

        {_, failures} ->
          {:error, failures}
      end
    end)
  end

  @doc """
  Creates a WireGuard peer on specified nodes using the MikrotikApi cluster helper.

  This ensures the peer is added consistently across all nodes.
  """
  def create_wireguard_peer(current_scope, interface_name, attrs, opts \\ []) do
    nodes = get_target_nodes(current_scope, opts)

    case nodes do
      [] ->
        {:error, :no_nodes}

      [primary | _rest] = all_nodes ->
        auth = Client.auth_from_node(primary)
        ips = Enum.map(all_nodes, & &1.host)
        api_opts = Client.get_opts(primary)

        # Build peer config for cluster helper
        peers = [attrs]

        {:ok, results} =
          MikrotikApi.wireguard_cluster_add_peers(auth, ips, interface_name, peers, api_opts)

        successes = map_results_to_nodes(results, all_nodes)

        Audit.log_peer_action("create", interface_name, attrs["public-key"] || "unknown", %{
          user_id: current_scope.user.id,
          details: %{interface: interface_name, attrs: attrs, nodes: Enum.map(all_nodes, & &1.id)}
        })

        {:ok, successes}
    end
  end

  @doc """
  Deletes a WireGuard peer from specified nodes.
  """
  def delete_wireguard_peer(current_scope, interface_name, public_key, opts \\ []) do
    nodes = get_target_nodes(current_scope, opts)

    results =
      Task.async_stream(
        nodes,
        fn node ->
          {node, Client.delete_wireguard_peer(node, interface_name, public_key)}
        end,
        timeout: 15_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, :timeout} -> {nil, {:error, :timeout}}
      end)

    case Enum.split_with(results, fn {_node, result} -> match?({:ok, _}, result) end) do
      {successes, []} ->
        Audit.log_peer_action("delete", interface_name, public_key, %{
          user_id: current_scope.user.id,
          details: %{nodes: Enum.map(nodes, & &1.id)}
        })

        {:ok, successes}

      {successes, failures} ->
        Audit.log_failure("delete", "wireguard_peer", "partial_failure", %{
          user_id: current_scope.user.id,
          resource_id: public_key,
          details: %{
            interface: interface_name,
            successes: length(successes),
            failures: length(failures)
          }
        })

        {:error, %{successes: successes, failures: failures}}
    end
  end

  @doc """
  Deletes a WireGuard peer from all active nodes in the cluster.
  """
  def delete_wireguard_peer_cluster(current_scope, interface_name, public_key) do
    delete_wireguard_peer(current_scope, interface_name, public_key, cluster_wide: true)
  end

  # GRE Interface Management

  @doc """
  Lists all GRE interfaces across all active nodes.
  """
  def list_gre_interfaces(_current_scope) do
    Cluster.list_active_nodes()
    |> Task.async_stream(
      fn node ->
        {node, Client.list_gre_interfaces(node)}
      end,
      timeout: 10_000,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, :timeout} -> {nil, {:error, :timeout}}
    end)
    |> Enum.reject(fn {node, _} -> is_nil(node) end)
  end

  @doc """
  Creates a GRE interface on specified nodes.
  """
  def create_gre_interface(current_scope, attrs, opts \\ []) do
    nodes = get_target_nodes(current_scope, opts)

    results =
      Task.async_stream(
        nodes,
        fn node ->
          {node, Client.create_gre_interface(node, attrs)}
        end,
        timeout: 15_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, :timeout} -> {nil, {:error, :timeout}}
      end)

    case Enum.split_with(results, fn {_node, result} -> match?({:ok, _}, result) end) do
      {successes, []} ->
        Audit.log_gre_action("create", attrs["name"] || "unknown", %{
          user_id: current_scope.user.id,
          details: %{attrs: attrs, nodes: Enum.map(nodes, & &1.id)}
        })

        {:ok, successes}

      {successes, failures} ->
        Audit.log_failure("create", "gre_interface", "partial_failure", %{
          user_id: current_scope.user.id,
          details: %{attrs: attrs, successes: length(successes), failures: length(failures)}
        })

        {:error, %{successes: successes, failures: failures}}
    end
  end

  @doc """
  Updates a GRE interface on specified nodes.
  """
  def update_gre_interface(current_scope, interface_id, attrs, opts \\ []) do
    nodes = get_target_nodes(current_scope, opts)

    results =
      Task.async_stream(
        nodes,
        fn node ->
          {node, Client.update_gre_interface(node, interface_id, attrs)}
        end,
        timeout: 15_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, :timeout} -> {nil, {:error, :timeout}}
      end)

    case Enum.split_with(results, fn {_node, result} -> match?({:ok, _}, result) end) do
      {successes, []} ->
        Audit.log_gre_action("update", interface_id, %{
          user_id: current_scope.user.id,
          details: %{attrs: attrs, nodes: Enum.map(nodes, & &1.id)}
        })

        {:ok, successes}

      {successes, failures} ->
        Audit.log_failure("update", "gre_interface", "partial_failure", %{
          user_id: current_scope.user.id,
          resource_id: interface_id,
          details: %{attrs: attrs, successes: length(successes), failures: length(failures)}
        })

        {:error, %{successes: successes, failures: failures}}
    end
  end

  @doc """
  Deletes a GRE interface from specified nodes.
  """
  def delete_gre_interface(current_scope, interface_id, opts \\ []) do
    nodes = get_target_nodes(current_scope, opts)

    results =
      Task.async_stream(
        nodes,
        fn node ->
          {node, Client.delete_gre_interface(node, interface_id)}
        end,
        timeout: 15_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, :timeout} -> {nil, {:error, :timeout}}
      end)

    case Enum.split_with(results, fn {_node, result} -> match?({:ok, _}, result) end) do
      {successes, []} ->
        Audit.log_gre_action("delete", interface_id, %{
          user_id: current_scope.user.id,
          details: %{nodes: Enum.map(nodes, & &1.id)}
        })

        {:ok, successes}

      {successes, failures} ->
        Audit.log_failure("delete", "gre_interface", "partial_failure", %{
          user_id: current_scope.user.id,
          resource_id: interface_id,
          details: %{successes: length(successes), failures: length(failures)}
        })

        {:error, %{successes: successes, failures: failures}}
    end
  end

  @doc """
  Deletes a GRE interface by name from all active nodes in the cluster.
  Finds the interface ID on each node and deletes it.
  """
  def delete_gre_interface_by_name(current_scope, interface_name) do
    nodes = Cluster.list_active_nodes()

    results =
      Task.async_stream(
        nodes,
        fn node ->
          # First find the interface by name on this node
          case Client.list_gre_interfaces(node) do
            {:ok, interfaces} ->
              case Enum.find(interfaces, &(&1["name"] == interface_name)) do
                nil ->
                  # Interface doesn't exist on this node, that's OK
                  {:ok, node, :not_found}

                interface ->
                  case Client.delete_gre_interface(node, interface[".id"]) do
                    {:ok, _} ->
                      {:ok, node, :deleted}

                    {:error, reason} ->
                      {:error, node, reason}
                  end
              end

            {:error, reason} ->
              {:error, node, reason}
          end
        end,
        timeout: 15_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, :timeout} -> {:error, nil, :timeout}
      end)
      |> Enum.reject(fn {_, node, _} -> is_nil(node) end)

    {successes, failures} = Enum.split_with(results, &match?({:ok, _, _}, &1))

    if successes != [] do
      Audit.log_gre_action("delete", interface_name, %{
        user_id: current_scope.user.id,
        details: %{cluster_wide: true, nodes: Enum.map(nodes, & &1.id)}
      })
    end

    {:ok, successes, failures}
  end

  @doc """
  Assigns an IP address to a GRE interface on all active nodes.
  """
  def assign_gre_ip(current_scope, interface_name, address) do
    nodes = Cluster.list_active_nodes()

    results =
      Task.async_stream(
        nodes,
        fn node ->
          attrs = %{"address" => address, "interface" => interface_name}
          {node, Client.ensure_address(node, attrs)}
        end,
        timeout: 15_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, :timeout} -> {nil, {:error, :timeout}}
      end)
      |> Enum.reject(fn {node, _} -> is_nil(node) end)

    case Enum.split_with(results, fn {_node, result} ->
           match?({:ok, _}, result)
         end) do
      {successes, []} ->
        Audit.log_gre_action("assign_ip", interface_name, %{
          user_id: current_scope.user.id,
          details: %{address: address, nodes: Enum.map(nodes, & &1.id)}
        })

        {:ok, successes}

      {_successes, failures} ->
        {:error, %{failures: failures}}
    end
  end

  @doc """
  Removes an IP address from a GRE interface on all active nodes.
  """
  def remove_gre_ip(current_scope, interface_name, address) do
    nodes = Cluster.list_active_nodes()

    results =
      Task.async_stream(
        nodes,
        fn node ->
          # Find the address ID on this node
          case Client.list_addresses(node, interface_name) do
            {:ok, addresses} ->
              case Enum.find(addresses, &(&1["address"] == address)) do
                nil ->
                  {node, {:ok, :not_found}}

                addr ->
                  {node, Client.delete_address(node, addr[".id"])}
              end

            error ->
              {node, error}
          end
        end,
        timeout: 15_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, :timeout} -> {nil, {:error, :timeout}}
      end)
      |> Enum.reject(fn {node, _} -> is_nil(node) end)

    case Enum.split_with(results, fn {_node, result} ->
           match?({:ok, _}, result)
         end) do
      {successes, []} ->
        Audit.log_address_action("delete", address, interface_name, %{
          user_id: current_scope.user.id,
          details: %{cluster_wide: true, nodes: Enum.map(nodes, & &1.id)}
        })

        {:ok, successes}

      {_successes, failures} ->
        {:error, %{failures: failures}}
    end
  end

  # IP Address Operations

  @doc """
  Lists all IP addresses across all active nodes.
  """
  def list_addresses(_current_scope) do
    Cluster.list_active_nodes()
    |> Task.async_stream(
      fn node ->
        {node, Client.list_addresses(node)}
      end,
      timeout: 10_000,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, :timeout} -> {nil, {:error, :timeout}}
    end)
    |> Enum.reject(fn {node, _} -> is_nil(node) end)
  end

  @doc """
  Creates an IP address assignment on specified nodes.
  """
  def create_address(current_scope, attrs, opts \\ []) do
    nodes = get_target_nodes(current_scope, opts)

    results =
      Task.async_stream(
        nodes,
        fn node ->
          {node, Client.create_address(node, attrs)}
        end,
        timeout: 15_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, :timeout} -> {nil, {:error, :timeout}}
      end)

    case Enum.split_with(results, fn {_node, result} -> match?({:ok, _}, result) end) do
      {successes, []} ->
        Audit.log_address_action(
          "create",
          attrs["address"] || "unknown",
          attrs["interface"] || "unknown",
          %{
            user_id: current_scope.user.id,
            details: %{attrs: attrs, nodes: Enum.map(nodes, & &1.id)}
          }
        )

        {:ok, successes}

      {successes, failures} ->
        Audit.log_failure("create", "ip_address", "partial_failure", %{
          user_id: current_scope.user.id,
          details: %{attrs: attrs, successes: length(successes), failures: length(failures)}
        })

        {:error, %{successes: successes, failures: failures}}
    end
  end

  @doc """
  Deletes an IP address from specified nodes.
  """
  def delete_address(current_scope, address_id, opts \\ []) do
    nodes = get_target_nodes(current_scope, opts)

    results =
      Task.async_stream(
        nodes,
        fn node ->
          {node, Client.delete_address(node, address_id)}
        end,
        timeout: 15_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, :timeout} -> {nil, {:error, :timeout}}
      end)

    case Enum.split_with(results, fn {_node, result} -> match?({:ok, _}, result) end) do
      {successes, []} ->
        Audit.log_address_action("delete", address_id, "unknown", %{
          user_id: current_scope.user.id,
          details: %{nodes: Enum.map(nodes, & &1.id)}
        })

        {:ok, successes}

      {successes, failures} ->
        Audit.log_failure("delete", "ip_address", "partial_failure", %{
          user_id: current_scope.user.id,
          resource_id: address_id,
          details: %{successes: length(successes), failures: length(failures)}
        })

        {:error, %{successes: successes, failures: failures}}
    end
  end

  # Private helper functions

  defp get_target_nodes(_current_scope, opts) do
    cond do
      Keyword.get(opts, :cluster_wide) ->
        Cluster.list_active_nodes()

      node_ids = Keyword.get(opts, :nodes) ->
        Enum.map(node_ids, &Cluster.get_node!(&1))

      true ->
        Cluster.list_active_nodes()
    end
  end

  # Map MikrotikApi results (keyed by IP) back to Node structs
  # Handles both tuple format {ip, result} and map format %{ip: ip, results: results}
  defp map_results_to_nodes(results, nodes) when is_list(results) do
    ip_to_node = Map.new(nodes, fn node -> {node.host, node} end)

    Enum.map(results, fn
      # Map format from newer MikrotikApi versions
      %{ip: ip, results: result} ->
        {Map.get(ip_to_node, ip), result}

      # Tuple format
      {ip, result} ->
        {Map.get(ip_to_node, ip), result}
    end)
    |> Enum.reject(fn {node, _} -> is_nil(node) end)
  end

  defp map_results_to_nodes(result, [node | _]) do
    [{node, result}]
  end
end
