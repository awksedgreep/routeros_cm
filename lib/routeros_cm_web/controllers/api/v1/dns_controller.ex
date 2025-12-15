defmodule RouterosCmWeb.API.V1.DNSController do
  @moduledoc """
  API controller for managing DNS records across the cluster.
  """
  use RouterosCmWeb, :controller

  import RouterosCmWeb.API.V1.Base

  alias RouterosCm.{Cluster, DNS}

  plug :require_scope, "dns:read" when action in [:index, :show, :settings]
  plug :require_scope, "dns:write" when action in [:create, :update, :delete, :update_settings, :flush_cache]

  @doc """
  List all DNS records across the cluster (grouped by name).

  GET /api/v1/dns/records
  Query params:
    - type: Filter by record type (A, AAAA, CNAME)
    - node: Filter by specific node name (returns per-node view)
  """
  def index(conn, params) do
    case DNS.list_dns_records(current_scope(conn)) do
      {:ok, results} ->
        records = group_records_by_name(results)

        # Apply type filter if specified
        filtered =
          case params["type"] do
            nil -> records
            type -> Enum.filter(records, &(&1.type == type))
          end

        json_response(conn, Enum.map(filtered, &record_to_json/1))
    end
  end

  @doc """
  Get a specific DNS record by name.

  GET /api/v1/dns/records/:name
  """
  def show(conn, %{"name" => name}) do
    case DNS.list_dns_records(current_scope(conn)) do
      {:ok, results} ->
        records = group_records_by_name(results)

        case Enum.find(records, &(&1.name == name)) do
          nil ->
            json_not_found(conn, "DNS record")

          record ->
            json_response(conn, record_to_json(record))
        end
    end
  end

  @doc """
  Create a new DNS record across the cluster.

  POST /api/v1/dns/records
  Body:
    - name: Domain name (required)
    - address: IP address for A/AAAA records
    - cname: Target for CNAME records
    - type: Record type (default: A)
    - ttl: Time to live (optional)
    - comment: Optional comment
  """
  def create(conn, params) do
    attrs = normalize_dns_params(params)

    case DNS.create_dns_record(current_scope(conn), attrs) do
      {:ok, successes, []} ->
        json_cluster_result(conn, "create", "dns_record", successes, [])

      {:ok, successes, failures} ->
        json_cluster_result(conn, "create", "dns_record", successes, failures)
    end
  end

  @doc """
  Update a DNS record by name across the cluster.

  PATCH/PUT /api/v1/dns/records/:name
  """
  def update(conn, %{"name" => name} = params) do
    attrs =
      params
      |> Map.drop(["name"])
      |> normalize_dns_params()
      |> Map.put("name", name)

    case DNS.update_dns_record_by_name(current_scope(conn), name, attrs) do
      {:ok, successes, []} ->
        json_cluster_result(conn, "update", "dns_record", successes, [])

      {:ok, successes, failures} ->
        json_cluster_result(conn, "update", "dns_record", successes, failures)
    end
  end

  @doc """
  Delete a DNS record by name from all nodes.

  DELETE /api/v1/dns/records/:name
  """
  def delete(conn, %{"name" => name}) do
    case DNS.delete_dns_record_by_name(current_scope(conn), name) do
      {:ok, successes, []} ->
        json_cluster_result(conn, "delete", "dns_record", successes, [])

      {:ok, successes, failures} ->
        json_cluster_result(conn, "delete", "dns_record", successes, failures)
    end
  end

  @doc """
  Get DNS server settings from the first active node.

  GET /api/v1/dns/settings
  """
  def settings(conn, _params) do
    case Cluster.list_active_nodes() do
      [] ->
        json_error(conn, "No active nodes available")

      [node | _] ->
        case DNS.get_dns_settings(node) do
          {:ok, settings} ->
            json_response(conn, settings_to_json(settings))

          {:error, reason} ->
            json_error(conn, %{error: format_error(reason)})
        end
    end
  end

  @doc """
  Update DNS server settings across the cluster.

  PATCH /api/v1/dns/settings
  """
  def update_settings(conn, params) do
    attrs = Map.take(params, ["servers", "allow-remote-requests", "cache-size", "cache-max-ttl"])

    case DNS.update_dns_settings(current_scope(conn), attrs) do
      {:ok, successes, []} ->
        json_cluster_result(conn, "update", "dns_settings", successes, [])

      {:ok, successes, failures} ->
        json_cluster_result(conn, "update", "dns_settings", successes, failures)
    end
  end

  @doc """
  Flush DNS cache on all nodes.

  POST /api/v1/dns/cache/flush
  """
  def flush_cache(conn, _params) do
    case DNS.flush_dns_cache(current_scope(conn)) do
      {:ok, successes, []} ->
        json_cluster_result(conn, "flush", "dns_cache", successes, [])

      {:ok, successes, failures} ->
        json_cluster_result(conn, "flush", "dns_cache", successes, failures)
    end
  end

  # Private helpers

  defp normalize_dns_params(params) do
    params
    |> Map.take(["name", "address", "cname", "type", "ttl", "comment"])
    |> Enum.reject(fn {_k, v} -> v == "" or is_nil(v) end)
    |> Map.new()
    |> then(fn attrs ->
      # Convert string keys to atom keys for the DNS context
      Map.new(attrs, fn {k, v} -> {String.to_existing_atom(k), v} end)
    end)
  rescue
    ArgumentError -> params
  end

  defp group_records_by_name(results) do
    results
    |> Enum.flat_map(fn
      {:ok, node, records} ->
        Enum.map(records, fn record ->
          {record["name"], %{node: node, record: record}}
        end)

      {:error, _node, _reason} ->
        []
    end)
    |> Enum.group_by(fn {name, _} -> name end, fn {_, data} -> data end)
    |> Enum.map(fn {name, nodes_data} ->
      first = List.first(nodes_data)

      %{
        name: name,
        type: first.record["type"] || "A",
        address: first.record["address"],
        cname: first.record["cname"],
        ttl: first.record["ttl"],
        comment: first.record["comment"],
        nodes:
          Enum.map(nodes_data, fn data ->
            %{
              node_name: data.node.name,
              node_id: data.node.id,
              record_id: data.record[".id"]
            }
          end)
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp record_to_json(record) do
    %{
      name: record.name,
      type: record.type,
      address: record.address,
      cname: record.cname,
      ttl: record.ttl,
      comment: record.comment,
      nodes: record.nodes
    }
  end

  defp settings_to_json(settings) do
    %{
      servers: settings["servers"],
      dynamic_servers: settings["dynamic-servers"],
      allow_remote_requests: settings["allow-remote-requests"],
      cache_size: settings["cache-size"],
      cache_max_ttl: settings["cache-max-ttl"],
      cache_used: settings["cache-used"]
    }
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
