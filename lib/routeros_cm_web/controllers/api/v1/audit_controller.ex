defmodule RouterosCmWeb.API.V1.AuditController do
  @moduledoc """
  API controller for querying audit logs.
  """
  use RouterosCmWeb, :controller

  import RouterosCmWeb.API.V1.Base

  alias RouterosCm.Audit

  plug :require_scope, "audit:read" when action in [:index, :show, :stats]

  @doc """
  List audit logs with filtering and pagination.

  GET /api/v1/audit
  Query params:
    - page: Page number (default: 1)
    - per_page: Items per page (default: 50, max: 100)
    - action: Filter by action (create, update, delete)
    - resource_type: Filter by resource type (dns_record, wireguard_interface, etc.)
    - success: Filter by success status (true/false)
    - from: Filter logs from this date (ISO 8601)
    - to: Filter logs until this date (ISO 8601)
  """
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

  @doc """
  Get a specific audit log entry.

  GET /api/v1/audit/:id
  """
  def show(conn, %{"id" => id}) do
    try do
      log = Audit.get_log!(id)
      json_response(conn, log_to_json(log))
    rescue
      Ecto.NoResultsError ->
        json_not_found(conn, "Audit log")
    end
  end

  @doc """
  Get audit log statistics.

  GET /api/v1/audit/stats
  """
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
