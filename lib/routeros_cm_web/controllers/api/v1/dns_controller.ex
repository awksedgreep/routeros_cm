defmodule RouterosCmWeb.API.V1.DNSController do
  @moduledoc """
  API controller for managing DNS records across the cluster.
  """
  use RouterosCmWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import RouterosCmWeb.API.V1.Base

  alias RouterosCm.{Cluster, DNS}
  alias OpenApiSpex.Schema
  alias RouterosCmWeb.ApiSchemas

  plug :require_scope, "dns:read" when action in [:index, :show, :settings]
  plug :require_scope, "dns:write" when action in [:create, :update, :delete, :update_settings, :flush_cache]

  tags ["DNS"]
  security [%{"bearer" => []}]

  operation :index,
    summary: "List DNS records",
    description: "Returns all DNS records across the cluster, grouped by name.",
    parameters: [
      type: [in: :query, type: :string, description: "Filter by record type (A, AAAA, CNAME)"]
    ],
    responses: [
      ok: {"DNS record list", "application/json", %Schema{
        type: :object,
        properties: %{data: %Schema{type: :array, items: ApiSchemas.DNSRecord}}
      }},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]

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

  operation :show,
    summary: "Get a DNS record",
    description: "Returns a specific DNS record by name.",
    parameters: [
      name: [in: :path, type: :string, description: "Domain name", required: true]
    ],
    responses: [
      ok: {"DNS record", "application/json", %Schema{
        type: :object,
        properties: %{data: ApiSchemas.DNSRecord}
      }},
      not_found: {"Not found", "application/json", ApiSchemas.Error},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]

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

  operation :create,
    summary: "Create a DNS record",
    description: "Creates a new DNS record across all nodes in the cluster.",
    request_body: {"DNS record parameters", "application/json", ApiSchemas.DNSRecordCreateRequest},
    responses: [
      ok: {"Creation result", "application/json", ApiSchemas.ClusterResult},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]

  def create(conn, params) do
    attrs = normalize_dns_params(params)

    case DNS.create_dns_record(current_scope(conn), attrs) do
      {:ok, successes, []} ->
        json_cluster_result(conn, "create", "dns_record", successes, [])

      {:ok, successes, failures} ->
        json_cluster_result(conn, "create", "dns_record", successes, failures)
    end
  end

  operation :update,
    summary: "Update a DNS record",
    description: "Updates a DNS record by name across all nodes.",
    parameters: [
      name: [in: :path, type: :string, description: "Domain name", required: true]
    ],
    request_body: {"DNS record parameters", "application/json", ApiSchemas.DNSRecordCreateRequest},
    responses: [
      ok: {"Update result", "application/json", ApiSchemas.ClusterResult},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]

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

  operation :delete,
    summary: "Delete a DNS record",
    description: "Deletes a DNS record by name from all nodes.",
    parameters: [
      name: [in: :path, type: :string, description: "Domain name", required: true]
    ],
    responses: [
      ok: {"Delete result", "application/json", ApiSchemas.ClusterResult},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]

  def delete(conn, %{"name" => name}) do
    case DNS.delete_dns_record_by_name(current_scope(conn), name) do
      {:ok, successes, []} ->
        json_cluster_result(conn, "delete", "dns_record", successes, [])

      {:ok, successes, failures} ->
        json_cluster_result(conn, "delete", "dns_record", successes, failures)
    end
  end

  operation :settings,
    summary: "Get DNS settings",
    description: "Returns DNS server settings from the first active node.",
    responses: [
      ok: {"DNS settings", "application/json", %Schema{
        type: :object,
        properties: %{
          data: %Schema{
            type: :object,
            properties: %{
              servers: %Schema{type: :string},
              dynamic_servers: %Schema{type: :string},
              allow_remote_requests: %Schema{type: :string},
              cache_size: %Schema{type: :string},
              cache_max_ttl: %Schema{type: :string},
              cache_used: %Schema{type: :string}
            }
          }
        }
      }},
      bad_request: {"Error", "application/json", ApiSchemas.Error},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]

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

  operation :update_settings,
    summary: "Update DNS settings",
    description: "Updates DNS server settings across all nodes.",
    request_body: {"DNS settings", "application/json", %Schema{
      type: :object,
      properties: %{
        servers: %Schema{type: :string, description: "Comma-separated list of DNS servers"},
        "allow-remote-requests": %Schema{type: :string, description: "yes/no"},
        "cache-size": %Schema{type: :string, description: "Cache size in KiB"},
        "cache-max-ttl": %Schema{type: :string, description: "Maximum TTL for cached entries"}
      }
    }},
    responses: [
      ok: {"Update result", "application/json", ApiSchemas.ClusterResult},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]

  def update_settings(conn, params) do
    attrs = Map.take(params, ["servers", "allow-remote-requests", "cache-size", "cache-max-ttl"])

    case DNS.update_dns_settings(current_scope(conn), attrs) do
      {:ok, successes, []} ->
        json_cluster_result(conn, "update", "dns_settings", successes, [])

      {:ok, successes, failures} ->
        json_cluster_result(conn, "update", "dns_settings", successes, failures)
    end
  end

  operation :flush_cache,
    summary: "Flush DNS cache",
    description: "Flushes the DNS cache on all nodes in the cluster.",
    responses: [
      ok: {"Flush result", "application/json", ApiSchemas.ClusterResult},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]

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
