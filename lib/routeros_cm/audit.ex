defmodule RouterosCm.Audit do
  @moduledoc """
  The Audit context for logging all operations.
  """

  import Ecto.Query, warn: false
  alias RouterosCm.Repo
  alias RouterosCm.Audit.Log

  @doc """
  Returns a paginated list of audit logs.

  ## Options
    * `:page` - Page number (default: 1)
    * `:per_page` - Items per page (default: 50)
    * `:limit` - Maximum number of logs to return (alias for per_page)
    * `:offset` - Number of logs to skip
    * `:action` - Filter by action
    * `:resource_type` - Filter by resource type
    * `:user_id` - Filter by user
    * `:success` - Filter by success status
    * `:from_date` - Filter logs from this date
    * `:to_date` - Filter logs until this date
  """
  def list_logs(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, Keyword.get(opts, :limit, 50))
    offset = Keyword.get(opts, :offset, (page - 1) * per_page)

    Log
    |> apply_filters(opts)
    |> order_by(desc: :inserted_at)
    |> limit(^per_page)
    |> offset(^offset)
    |> preload(:user)
    |> Repo.all()
  end

  @doc """
  Returns recent audit logs for display on the dashboard.
  """
  def list_recent_logs(limit \\ 10) do
    Log
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> preload(:user)
    |> Repo.all()
  end

  @doc """
  Gets a single audit log entry.
  """
  def get_log!(id) do
    Log
    |> preload(:user)
    |> Repo.get!(id)
  end

  @doc """
  Creates an audit log entry.
  """
  def create_log(attrs \\ %{}) do
    %Log{}
    |> Log.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Logs a successful operation.
  """
  def log_success(action, resource_type, attrs \\ %{}) do
    attrs
    |> Map.merge(%{
      action: to_string(action),
      resource_type: to_string(resource_type),
      success: true
    })
    |> create_log()
  end

  @doc """
  Logs a failed operation.
  """
  def log_failure(action, resource_type, error, attrs \\ %{}) do
    attrs
    |> Map.merge(%{
      action: to_string(action),
      resource_type: to_string(resource_type),
      success: false,
      error_message: inspect(error)
    })
    |> create_log()
  end

  @doc """
  Logs a cluster operation (node create/update/delete).
  """
  def log_cluster_action(user_id, action, details \\ %{}) do
    create_log(%{
      user_id: user_id,
      action: action,
      resource_type: "cluster",
      details: details,
      success: true
    })
  end

  @doc """
  Logs a node operation (create/update/delete).
  Accepts either a Node struct or audit options map.
  """
  def log_node_action(action, node_or_opts, opts \\ %{})

  def log_node_action(action, %RouterosCm.Cluster.Node{} = node, opts) do
    create_log(
      Map.merge(opts, %{
        action: to_string(action),
        resource_type: "node",
        resource_id: node.id,
        details: %{node_name: node.name, host: node.host},
        success: true
      })
    )
  end

  def log_node_action(action, opts, _) when is_map(opts) do
    create_log(
      Map.merge(opts, %{
        action: to_string(action),
        resource_type: "node",
        success: true
      })
    )
  end

  @doc """
  Logs a WireGuard operation.
  """
  def log_wireguard_action(action, interface_name, opts \\ %{}) do
    create_log(
      Map.merge(opts, %{
        action: to_string(action),
        resource_type: "wireguard_interface",
        resource_id: interface_name,
        success: true
      })
    )
  end

  @doc """
  Logs a GRE operation.
  """
  def log_gre_action(action, tunnel_name, opts \\ %{}) do
    create_log(
      Map.merge(opts, %{
        action: to_string(action),
        resource_type: "gre_interface",
        resource_id: tunnel_name,
        success: true
      })
    )
  end

  @doc """
  Logs a peer operation.
  """
  def log_peer_action(action, interface_name, public_key, opts \\ %{}) do
    create_log(
      Map.merge(opts, %{
        action: to_string(action),
        resource_type: "wireguard_peer",
        resource_id: "#{interface_name}/#{String.slice(public_key, 0..7)}...",
        success: true
      })
    )
  end

  @doc """
  Logs an IP address operation.
  """
  def log_address_action(action, address, interface, opts \\ %{}) do
    create_log(
      Map.merge(opts, %{
        action: to_string(action),
        resource_type: "ip_address",
        resource_id: "#{address} on #{interface}",
        success: true
      })
    )
  end

  @doc """
  Logs a DNS operation.
  """
  def log_dns_action(action, record_name, opts \\ %{}) do
    create_log(
      Map.merge(opts, %{
        action: to_string(action),
        resource_type: "dns_record",
        resource_id: record_name,
        success: true
      })
    )
  end

  @doc """
  Logs a RouterOS user operation.
  """
  def log_routeros_user_action(action, username, opts \\ %{}) do
    create_log(
      Map.merge(opts, %{
        action: to_string(action),
        resource_type: "routeros_user",
        resource_id: username,
        success: true
      })
    )
  end

  @doc """
  Returns the count of audit logs.
  """
  def count_logs(opts \\ []) do
    Log
    |> apply_filters(opts)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Returns audit log statistics.
  """
  def get_stats do
    today = Date.utc_today()
    start_of_day = DateTime.new!(today, ~T[00:00:00], "Etc/UTC")

    %{
      total: Repo.aggregate(Log, :count, :id),
      today: Repo.one(from l in Log, where: l.inserted_at >= ^start_of_day, select: count(l.id))
    }
  end

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:action, action}, q when not is_nil(action) ->
        where(q, [l], l.action == ^action)

      {:resource_type, type}, q when not is_nil(type) ->
        where(q, [l], l.resource_type == ^type)

      {:user_id, user_id}, q when not is_nil(user_id) ->
        where(q, [l], l.user_id == ^user_id)

      {:success, success}, q when is_boolean(success) ->
        where(q, [l], l.success == ^success)

      {:from_date, date}, q when not is_nil(date) ->
        where(q, [l], l.inserted_at >= ^date)

      {:to_date, date}, q when not is_nil(date) ->
        where(q, [l], l.inserted_at <= ^date)

      _other, q ->
        q
    end)
  end
end
