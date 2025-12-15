defmodule RouterosCm.DNS do
  @moduledoc """
  The DNS context for managing static DNS records and server settings.

  This context follows the tunnel_manager pattern - DNS records are managed
  directly via the RouterOS API without local database storage.
  """

  alias RouterosCm.Audit
  alias RouterosCm.Cluster
  alias RouterosCm.MikroTik.Client

  require Logger

  @doc """
  Lists all DNS records across the cluster or specific nodes.

  ## Options
    * `:cluster_wide` - If true, fetches from all active nodes (default: true)
    * `:nodes` - List of specific node IDs to query

  Returns `{:ok, results}` where results is a list of `{:ok, node, records}` or `{:error, node, reason}` tuples.
  """
  def list_dns_records(current_scope, opts \\ []) do
    target_nodes = get_target_nodes(opts)

    results =
      target_nodes
      |> Task.async_stream(
        fn node ->
          case Client.list_dns_records(node) do
            {:ok, records} ->
              {:ok, node, records}

            {:error, reason} ->
              Logger.error("Failed to list DNS records on #{node.name}: #{inspect(reason)}")
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

    {successes, failures} = Enum.split_with(results, &match?({:ok, _, _}, &1))

    if failures != [] do
      Audit.log_failure(
        "list",
        "dns_record",
        "partial_failure",
        %{
          user_id: current_scope.user.id,
          details: %{failures: length(failures), successes: length(successes)}
        }
      )
    end

    {:ok, results}
  end

  @doc """
  Creates a DNS record across specified nodes.

  ## Attributes
    * `:name` - Domain name (required)
    * `:address` - IP address (for A/AAAA records)
    * `:cname` - CNAME target (for CNAME records)
    * `:ttl` - Time to live (optional)
    * `:type` - Record type (optional, defaults to A)
  """
  def create_dns_record(current_scope, attrs, opts \\ []) do
    target_nodes = get_target_nodes(opts)
    # Filter out empty string values
    clean_attrs = attrs |> Enum.reject(fn {_k, v} -> v == "" end) |> Map.new()

    results =
      target_nodes
      |> Task.async_stream(
        fn node ->
          case Client.create_dns_record(node, clean_attrs) do
            {:ok, record} ->
              Audit.log_dns_action(:create, attrs[:name] || "unknown", %{
                user_id: current_scope.user.id,
                details: %{node: node.name, record: attrs}
              })

              {:ok, node, record}

            {:error, reason} ->
              Logger.error("Failed to create DNS record on #{node.name}: #{inspect(reason)}")
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

    {successes, failures} = Enum.split_with(results, &match?({:ok, _, _}, &1))

    if failures != [] do
      Audit.log_failure(
        "create",
        "dns_record",
        "partial_failure",
        %{
          user_id: current_scope.user.id,
          details: %{name: attrs[:name], failures: length(failures), successes: length(successes)}
        }
      )
    end

    {:ok, successes, failures}
  end

  @doc """
  Updates a DNS record across specified nodes.
  """
  def update_dns_record(current_scope, record_id, attrs, opts \\ []) do
    target_nodes = get_target_nodes(opts)

    results =
      target_nodes
      |> Task.async_stream(
        fn node ->
          case Client.update_dns_record(node, record_id, attrs) do
            {:ok, record} ->
              Audit.log_dns_action(:update, attrs[:name] || record_id, %{
                user_id: current_scope.user.id,
                details: %{node: node.name, record_id: record_id}
              })

              {:ok, node, record}

            {:error, reason} ->
              Logger.error("Failed to update DNS record on #{node.name}: #{inspect(reason)}")
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

    {successes, failures} = Enum.split_with(results, &match?({:ok, _, _}, &1))

    if failures != [] do
      Audit.log_failure(
        "update",
        "dns_record",
        "partial_failure",
        %{user_id: current_scope.user.id, details: %{record_id: record_id, failures: length(failures)}}
      )
    end

    {:ok, successes, failures}
  end

  @doc """
  Deletes a DNS record from specified nodes.
  """
  def delete_dns_record(current_scope, record_id, opts \\ []) do
    target_nodes = get_target_nodes(opts)

    results =
      target_nodes
      |> Task.async_stream(
        fn node ->
          case Client.delete_dns_record(node, record_id) do
            {:ok, _} ->
              Audit.log_dns_action(:delete, record_id, %{
                user_id: current_scope.user.id,
                details: %{node: node.name}
              })

              {:ok, node}

            {:error, reason} ->
              Logger.error("Failed to delete DNS record on #{node.name}: #{inspect(reason)}")
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

    {successes, failures} = Enum.split_with(results, &match?({:ok, _}, &1))

    if failures != [] do
      Audit.log_failure(
        "delete",
        "dns_record",
        "partial_failure",
        %{user_id: current_scope.user.id, details: %{record_id: record_id, failures: length(failures)}}
      )
    end

    {:ok, successes, failures}
  end

  @doc """
  Deletes a DNS record by name from all active nodes in the cluster.
  Finds the record ID on each node and deletes it.
  """
  def delete_dns_record_by_name(current_scope, record_name) do
    target_nodes = Cluster.list_active_nodes()

    results =
      target_nodes
      |> Task.async_stream(
        fn node ->
          # First find the record by name on this node
          case Client.list_dns_records(node) do
            {:ok, records} ->
              case Enum.find(records, &(&1["name"] == record_name)) do
                nil ->
                  # Record doesn't exist on this node, that's OK
                  {:ok, node, :not_found}

                record ->
                  case Client.delete_dns_record(node, record[".id"]) do
                    {:ok, _} ->
                      Audit.log_dns_action(:delete, record_name, %{
                        user_id: current_scope.user.id,
                        details: %{node: node.name}
                      })

                      {:ok, node, :deleted}

                    {:error, reason} ->
                      Logger.error(
                        "Failed to delete DNS record '#{record_name}' on #{node.name}: #{inspect(reason)}"
                      )

                      {:error, node, reason}
                  end
              end

            {:error, reason} ->
              Logger.error("Failed to list DNS records on #{node.name}: #{inspect(reason)}")
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

    {successes, failures} = Enum.split_with(results, &match?({:ok, _, _}, &1))

    if failures != [] do
      Audit.log_failure(
        "delete",
        "dns_record",
        "partial_failure",
        %{user_id: current_scope.user.id, details: %{name: record_name, failures: length(failures)}}
      )
    end

    {:ok, successes, failures}
  end

  @doc """
  Updates a DNS record by name across all active nodes in the cluster.
  Finds the record ID on each node and updates it.
  """
  def update_dns_record_by_name(current_scope, record_name, attrs) do
    target_nodes = Cluster.list_active_nodes()
    # Filter out empty string values
    clean_attrs = attrs |> Enum.reject(fn {_k, v} -> v == "" end) |> Map.new()

    results =
      target_nodes
      |> Task.async_stream(
        fn node ->
          # First find the record by name on this node
          case Client.list_dns_records(node) do
            {:ok, records} ->
              case Enum.find(records, &(&1["name"] == record_name)) do
                nil ->
                  # Record doesn't exist on this node - create it
                  case Client.create_dns_record(node, clean_attrs) do
                    {:ok, record} ->
                      {:ok, node, {:created, record}}

                    {:error, reason} ->
                      {:error, node, reason}
                  end

                record ->
                  case Client.update_dns_record(node, record[".id"], clean_attrs) do
                    {:ok, updated} ->
                      Audit.log_dns_action(:update, record_name, %{
                        user_id: current_scope.user.id,
                        details: %{node: node.name, attrs: clean_attrs}
                      })

                      {:ok, node, {:updated, updated}}

                    {:error, reason} ->
                      Logger.error(
                        "Failed to update DNS record '#{record_name}' on #{node.name}: #{inspect(reason)}"
                      )

                      {:error, node, reason}
                  end
              end

            {:error, reason} ->
              Logger.error("Failed to list DNS records on #{node.name}: #{inspect(reason)}")
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

    {successes, failures} = Enum.split_with(results, &match?({:ok, _, _}, &1))

    if failures != [] do
      Audit.log_failure(
        "update",
        "dns_record",
        "partial_failure",
        %{user_id: current_scope.user.id, details: %{name: record_name, failures: length(failures)}}
      )
    end

    {:ok, successes, failures}
  end

  @doc """
  Gets DNS server settings from a node.
  """
  def get_dns_settings(%RouterosCm.Cluster.Node{} = node) do
    Client.get_dns_settings(node)
  end

  @doc """
  Updates DNS server settings on specified nodes.
  """
  def update_dns_settings(current_scope, attrs, opts \\ []) do
    target_nodes = get_target_nodes(opts)

    results =
      target_nodes
      |> Task.async_stream(
        fn node ->
          case Client.update_dns_settings(node, attrs) do
            {:ok, settings} ->
              Audit.log_dns_action(:update_settings, "server", %{
                user_id: current_scope.user.id,
                details: %{node: node.name, settings: attrs}
              })

              {:ok, node, settings}

            {:error, reason} ->
              Logger.error("Failed to update DNS settings on #{node.name}: #{inspect(reason)}")
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

    {successes, failures} = Enum.split_with(results, &match?({:ok, _, _}, &1))

    if failures != [] do
      Audit.log_failure(
        "update_settings",
        "dns_server",
        "partial_failure",
        %{user_id: current_scope.user.id, details: %{failures: length(failures)}}
      )
    end

    {:ok, successes, failures}
  end

  @doc """
  Lists DNS cache entries from a node.
  """
  def list_dns_cache(%RouterosCm.Cluster.Node{} = node) do
    Client.list_dns_cache(node)
  end

  @doc """
  Flushes DNS cache on specified nodes.
  """
  def flush_dns_cache(current_scope, opts \\ []) do
    target_nodes = get_target_nodes(opts)

    results =
      target_nodes
      |> Task.async_stream(
        fn node ->
          case Client.flush_dns_cache(node) do
            {:ok, _} ->
              Audit.log_dns_action(:flush_cache, "cache", %{
                user_id: current_scope.user.id,
                details: %{node: node.name}
              })

              {:ok, node}

            {:error, reason} ->
              Logger.error("Failed to flush DNS cache on #{node.name}: #{inspect(reason)}")
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

    {successes, failures} = Enum.split_with(results, &match?({:ok, _}, &1))

    if failures != [] do
      Audit.log_failure(
        "flush_cache",
        "dns_cache",
        "partial_failure",
        %{user_id: current_scope.user.id, details: %{failures: length(failures)}}
      )
    end

    {:ok, successes, failures}
  end

  # Private helpers

  defp get_target_nodes(opts) do
    cond do
      Keyword.get(opts, :cluster_wide, true) ->
        Cluster.list_active_nodes()

      node_ids = Keyword.get(opts, :nodes) ->
        Enum.map(node_ids, &Cluster.get_node!/1)

      true ->
        Cluster.list_active_nodes()
    end
  end
end
