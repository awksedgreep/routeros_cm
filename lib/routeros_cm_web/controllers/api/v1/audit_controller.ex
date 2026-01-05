defmodule RouterosCmWeb.API.V1.AuditController do
  @moduledoc """
  API controller for querying audit logs.
  """
  use RouterosCmWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import RouterosCmWeb.API.V1.Base

  alias RouterosCm.Audit
  alias OpenApiSpex.Schema
  alias RouterosCmWeb.ApiSchemas

  plug :require_scope, "audit:read" when action in [:index, :show, :stats]

  tags ["Audit"]
  security [%{"bearer" => []}]

  operation :index,
    summary: "List audit logs",
    description: "Returns paginated audit logs with optional filtering.",
    parameters: [
      page: [in: :query, type: :integer, description: "Page number (default: 1)"],
      per_page: [in: :query, type: :integer, description: "Items per page (default: 50, max: 100)"],
      action: [in: :query, type: :string, description: "Filter by action (create, update, delete)"],
      resource_type: [in: :query, type: :string, description: "Filter by resource type"],
      success: [in: :query, type: :boolean, description: "Filter by success status"],
      from: [in: :query, type: :string, description: "Filter from date (ISO 8601)"],
      to: [in: :query, type: :string, description: "Filter until date (ISO 8601)"]
    ],
    responses: [
      ok: {"Audit log list", "application/json", %Schema{
        type: :object,
        properties: %{
          data: %Schema{type: :array, items: ApiSchemas.AuditLog},
          meta: %Schema{
            type: :object,
            properties: %{
              total: %Schema{type: :integer},
              page: %Schema{type: :integer},
              per_page: %Schema{type: :integer},
              total_pages: %Schema{type: :integer}
            }
          }
        }
      }},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]

  def index(conn, params) do
    page = parse_int(params["page"], 1)
    per_page = parse_int(params["per_page"], 50) |> min(100)

    opts =
      []
      |> add_filter(:action, params["action"])
      |> add_filter(:resource_type, params["resource_type"])
      |> add_filter(:success, parse_boolean(params["success"]))
      |> add_filter(:from_date, parse_datetime(params["from"]))
      |> add_filter(:to_date, parse_datetime(params["to"]))
      |> Keyword.put(:page, page)
      |> Keyword.put(:per_page, per_page)

    logs = Audit.list_logs(opts)
    total = Audit.count_logs(opts)

    json_response(
      conn,
      Enum.map(logs, &log_to_json/1),
      %{
        total: total,
        page: page,
        per_page: per_page,
        total_pages: ceil(total / per_page)
      }
    )
  end

  operation :show,
    summary: "Get an audit log entry",
    description: "Returns a specific audit log entry by ID.",
    parameters: [
      id: [in: :path, type: :integer, description: "Audit log ID", required: true]
    ],
    responses: [
      ok: {"Audit log entry", "application/json", %Schema{
        type: :object,
        properties: %{data: ApiSchemas.AuditLog}
      }},
      not_found: {"Not found", "application/json", ApiSchemas.Error},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]

  def show(conn, %{"id" => id}) do
    try do
      log = Audit.get_log!(id)
      json_response(conn, log_to_json(log))
    rescue
      Ecto.NoResultsError ->
        json_not_found(conn, "Audit log")
    end
  end

  operation :stats,
    summary: "Get audit statistics",
    description: "Returns audit log statistics.",
    responses: [
      ok: {"Audit statistics", "application/json", ApiSchemas.AuditStats},
      unauthorized: {"Unauthorized", "application/json", ApiSchemas.Error}
    ]

  def stats(conn, _params) do
    stats = Audit.get_stats()

    json_response(conn, %{
      total: stats.total,
      today: stats.today
    })
  end

  # Private helpers

  defp log_to_json(log) do
    %{
      id: log.id,
      action: log.action,
      resource_type: log.resource_type,
      resource_id: log.resource_id,
      success: log.success,
      details: log.details,
      ip_address: log.ip_address,
      user: user_to_json(log.user),
      inserted_at: log.inserted_at
    }
  end

  defp user_to_json(nil), do: nil

  defp user_to_json(user) do
    %{
      id: user.id,
      email: user.email
    }
  end

  defp add_filter(opts, _key, nil), do: opts
  defp add_filter(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_int(nil, default), do: default
  defp parse_int("", default), do: default

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(value, _default) when is_integer(value), do: value

  defp parse_boolean(nil), do: nil
  defp parse_boolean("true"), do: true
  defp parse_boolean("false"), do: false
  defp parse_boolean(value) when is_boolean(value), do: value
  defp parse_boolean(_), do: nil

  defp parse_datetime(nil), do: nil
  defp parse_datetime(""), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _} -> datetime
      {:error, _} -> nil
    end
  end
end
