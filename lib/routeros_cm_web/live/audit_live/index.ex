defmodule RouterosCmWeb.AuditLive.Index do
  @moduledoc """
  LiveView for viewing audit logs.
  """
  use RouterosCmWeb, :live_view

  alias RouterosCm.Audit

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Audit Logs")
     |> assign(:page, 1)
     |> assign(:filter_action, nil)
     |> assign(:filter_resource_type, nil)
     |> stream(:logs, Audit.list_logs())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    page = String.to_integer(params["page"] || "1")
    action = params["action"]
    resource_type = params["resource_type"]

    logs =
      Audit.list_logs(
        page: page,
        action: action,
        resource_type: resource_type
      )

    {:noreply,
     socket
     |> assign(:page, page)
     |> assign(:filter_action, action)
     |> assign(:filter_resource_type, resource_type)
     |> stream(:logs, logs, reset: true)}
  end

  @impl true
  def handle_event("filter", %{"action" => action, "resource_type" => resource_type}, socket) do
    params =
      %{}
      |> maybe_add_param("action", action)
      |> maybe_add_param("resource_type", resource_type)

    {:noreply, push_patch(socket, to: ~p"/audit?#{params}")}
  end

  @impl true
  def handle_event("clear_filters", _, socket) do
    {:noreply, push_patch(socket, to: ~p"/audit")}
  end

  defp maybe_add_param(params, _key, ""), do: params
  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, key, value), do: Map.put(params, key, value)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <%!-- Header --%>
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold">Audit Logs</h1>
            <p class="text-base-content/70">Track all operations and changes</p>
          </div>
        </div>

        <%!-- Filters --%>
        <div class="card bg-base-100 shadow-sm border border-base-300">
          <div class="card-body p-4">
            <form phx-change="filter" class="flex flex-wrap items-end gap-4">
              <div class="form-control">
                <label class="label py-1">
                  <span class="label-text text-sm">Action</span>
                </label>
                <select
                  name="action"
                  class="select select-sm select-bordered"
                  value={@filter_action || ""}
                >
                  <option value="">All Actions</option>
                  <option :for={action <- action_types()} value={action}>
                    {humanize_action(action)}
                  </option>
                </select>
              </div>

              <div class="form-control">
                <label class="label py-1">
                  <span class="label-text text-sm">Resource Type</span>
                </label>
                <select
                  name="resource_type"
                  class="select select-sm select-bordered"
                  value={@filter_resource_type || ""}
                >
                  <option value="">All Types</option>
                  <option :for={type <- resource_types()} value={type}>
                    {humanize_resource_type(type)}
                  </option>
                </select>
              </div>

              <button
                :if={@filter_action || @filter_resource_type}
                type="button"
                phx-click="clear_filters"
                class="btn btn-ghost btn-sm"
              >
                <.icon name="hero-x-mark" class="size-4" /> Clear Filters
              </button>
            </form>
          </div>
        </div>

        <%!-- Logs Table --%>
        <div class="card bg-base-100 shadow-sm border border-base-300">
          <div class="card-body p-0">
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>Timestamp</th>
                    <th>Action</th>
                    <th>Resource</th>
                    <th>Status</th>
                    <th>Details</th>
                  </tr>
                </thead>
                <tbody id="audit-logs" phx-update="stream">
                  <tr :for={{dom_id, log} <- @streams.logs} id={dom_id} class="hover:bg-base-200/50">
                    <td class="text-sm text-base-content/70 whitespace-nowrap">
                      {format_timestamp(log.inserted_at)}
                    </td>
                    <td>
                      <.action_badge action={log.action} />
                    </td>
                    <td>
                      <.resource_badge type={log.resource_type} />
                    </td>
                    <td>
                      <%= if log.success do %>
                        <span class="badge badge-success badge-sm">Success</span>
                      <% else %>
                        <span class="badge badge-error badge-sm">Failed</span>
                      <% end %>
                    </td>
                    <td class="text-sm text-base-content/70 max-w-md">
                      {format_details(log.details)}
                    </td>
                  </tr>
                </tbody>
              </table>

              <div
                :if={@streams.logs.inserts == []}
                class="text-center py-12 text-base-content/50"
              >
                <.icon name="hero-clipboard-document-list" class="size-12 mx-auto mb-3 opacity-50" />
                <p class="font-medium">No audit logs yet</p>
                <p class="text-sm">Activity will be logged as you manage the cluster.</p>
              </div>
            </div>
          </div>
        </div>

        <%!-- Pagination --%>
        <div class="flex justify-center">
          <div class="join">
            <.link
              patch={
                ~p"/audit?#{pagination_params(@filter_action, @filter_resource_type, @page - 1)}"
              }
              class={["join-item btn btn-sm", @page <= 1 && "btn-disabled"]}
            >
              <.icon name="hero-chevron-left" class="size-4" />
            </.link>
            <button class="join-item btn btn-sm btn-active">Page {@page}</button>
            <.link
              patch={
                ~p"/audit?#{pagination_params(@filter_action, @filter_resource_type, @page + 1)}"
              }
              class="join-item btn btn-sm"
            >
              <.icon name="hero-chevron-right" class="size-4" />
            </.link>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp action_badge(assigns) do
    colors = %{
      "create" => "badge-success",
      "update" => "badge-info",
      "delete" => "badge-error",
      "enable" => "badge-success",
      "disable" => "badge-warning",
      "test_connection" => "badge-info"
    }

    assigns = assign(assigns, :color, Map.get(colors, assigns.action, "badge-ghost"))

    ~H"""
    <span class={["badge badge-sm", @color]}>
      {humanize_action(@action)}
    </span>
    """
  end

  defp resource_badge(assigns) do
    icons = %{
      "node" => "hero-server",
      "wireguard_interface" => "hero-shield-check",
      "wireguard_peer" => "hero-users",
      "gre_tunnel" => "hero-arrows-right-left",
      "ip_address" => "hero-globe-alt"
    }

    assigns = assign(assigns, :icon, Map.get(icons, assigns.type, "hero-cube"))

    ~H"""
    <div class="flex items-center gap-2">
      <.icon name={@icon} class="size-4 text-base-content/50" />
      <span class="font-medium">{humanize_resource_type(@type)}</span>
    </div>
    """
  end

  defp action_types do
    ~w(create update delete enable disable test_connection)
  end

  defp resource_types do
    ~w(node wireguard_interface wireguard_peer gre_tunnel ip_address)
  end

  defp humanize_action("create"), do: "Created"
  defp humanize_action("update"), do: "Updated"
  defp humanize_action("delete"), do: "Deleted"
  defp humanize_action("enable"), do: "Enabled"
  defp humanize_action("disable"), do: "Disabled"
  defp humanize_action("test_connection"), do: "Tested"
  defp humanize_action(action), do: String.capitalize(action)

  defp humanize_resource_type("node"), do: "Node"
  defp humanize_resource_type("wireguard_interface"), do: "WireGuard Interface"
  defp humanize_resource_type("wireguard_peer"), do: "WireGuard Peer"
  defp humanize_resource_type("gre_tunnel"), do: "GRE Tunnel"
  defp humanize_resource_type("ip_address"), do: "IP Address"
  defp humanize_resource_type(type), do: String.capitalize(type)

  defp format_timestamp(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
  end

  defp format_details(nil), do: "—"

  defp format_details(details) when is_map(details) do
    details
    |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v)}" end)
    |> Enum.join(", ")
  end

  defp format_details(details), do: to_string(details)

  defp pagination_params(action, resource_type, page) do
    %{}
    |> maybe_add_param("action", action)
    |> maybe_add_param("resource_type", resource_type)
    |> Map.put("page", page)
  end
end
