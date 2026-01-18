defmodule RouterosCmWeb.DashboardLive do
  @moduledoc """
  LiveView for the main dashboard showing cluster health overview.
  """
  use RouterosCmWeb, :live_view

  alias RouterosCm.{Audit, Cluster}
  alias RouterosCmWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Process.send_after(self(), :refresh_health, 10_000)
    end

    {:ok, assign_stats(socket)}
  end

  @impl true
  def handle_info(:refresh_health, socket) do
    Process.send_after(self(), :refresh_health, 10_000)
    {:noreply, assign(socket, :health, Cluster.fetch_cluster_health())}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, assign_stats(socket)}
  end

  defp assign_stats(socket) do
    stats = Cluster.get_cluster_stats()
    nodes = Cluster.list_nodes()
    recent_logs = Audit.list_recent_logs(10)
    can_write = can_write?(socket)
    health = Cluster.fetch_cluster_health()

    socket
    |> assign(:page_title, "Dashboard")
    |> assign(:stats, stats)
    |> assign(:nodes, nodes)
    |> assign(:recent_logs, recent_logs)
    |> assign(:can_write, can_write)
    |> assign(:health, health)
  end

  defp can_write?(socket) do
    case socket.assigns[:current_scope] do
      %{user: user} when not is_nil(user) -> true
      _ -> false
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <%!-- Welcome Header --%>
        <div>
          <h1 class="text-3xl font-bold">Dashboard</h1>
          <p class="text-base-content/70">Overview of your RouterOS cluster</p>
        </div>

        <%!-- Stats Cards --%>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <.stat_card
            title="Total Nodes"
            value={@stats.total_nodes}
            icon="hero-server"
            color="primary"
          />
          <.stat_card
            title="Online Nodes"
            value={@stats.active_nodes}
            icon="hero-check-circle"
            color="success"
          />
          <.stat_card
            title="Offline Nodes"
            value={@stats.offline_nodes}
            icon="hero-x-circle"
            color="error"
          />
          <.stat_card
            title="Total Resources"
            value={length(@recent_logs)}
            icon="hero-cube"
            color="info"
          />
        </div>

        <%!-- Cluster Health & Quick Actions --%>
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <%!-- Cluster Health --%>
          <div class="lg:col-span-2 card bg-base-100 shadow-sm border border-base-300">
            <div class="card-body">
              <div class="flex items-center justify-between">
                <h2 class="card-title">
                  <.icon name="hero-server-stack" class="size-5" /> Cluster Health
                </h2>
                <button phx-click="refresh" class="btn btn-ghost btn-xs gap-1">
                  <.icon name="hero-arrow-path" class="size-3" /> Refresh
                </button>
              </div>

              <%= if @nodes == [] do %>
                <div class="text-center text-base-content/50 py-8">
                  <.icon name="hero-server" class="w-12 h-12 mx-auto mb-2 opacity-50" />
                  <p class="mb-2">No nodes configured yet.</p>
                  <%= if @can_write do %>
                    <.link navigate={~p"/nodes/new"} class="link link-primary">
                      Add your first node
                    </.link>
                  <% end %>
                </div>
              <% else %>
                <div class="space-y-4">
                  <%= for node <- @nodes do %>
                    <% node_health = get_node_health(@health, node.id) %>
                    <div class="p-4 rounded-lg bg-base-200/50 border border-base-300">
                      <div class="flex items-center justify-between mb-3">
                        <div class="flex items-center gap-3">
                          <span class="font-semibold">{node.name}</span>
                          <.status_badge status={node.status} />
                        </div>
                        <span class="text-xs text-base-content/60 font-mono">
                          {node.host}:{node.port}
                        </span>
                      </div>

                      <%= if node_health do %>
                        <div class="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
                          <%!-- CPU --%>
                          <div>
                            <div class="flex justify-between text-xs text-base-content/70 mb-1">
                              <span>CPU</span>
                              <span>{node_health.cpu_load}%</span>
                            </div>
                            <progress
                              class={[
                                "progress w-full h-2",
                                cpu_color_class(node_health.cpu_load)
                              ]}
                              value={node_health.cpu_load}
                              max="100"
                            >
                            </progress>
                          </div>

                          <%!-- Memory --%>
                          <div>
                            <% mem_pct = memory_percent(node_health) %>
                            <div class="flex justify-between text-xs text-base-content/70 mb-1">
                              <span>Memory</span>
                              <span>{mem_pct}%</span>
                            </div>
                            <progress
                              class={["progress w-full h-2", memory_color_class(mem_pct)]}
                              value={mem_pct}
                              max="100"
                            >
                            </progress>
                          </div>

                          <%!-- Version & Uptime --%>
                          <div>
                            <span class="text-xs text-base-content/70">Version</span>
                            <div class="font-mono text-xs">{node_health.version || "-"}</div>
                          </div>

                          <div>
                            <span class="text-xs text-base-content/70">Uptime</span>
                            <div class="font-mono text-xs">{node_health.uptime || "-"}</div>
                          </div>
                        </div>

                        <%!-- System info row --%>
                        <div class="flex gap-4 mt-3 text-xs text-base-content/60">
                          <%= if node_health.board_name do %>
                            <span title="Board">{node_health.board_name}</span>
                          <% end %>
                          <%= if node_health.architecture do %>
                            <span title="Architecture">{node_health.architecture}</span>
                          <% end %>
                          <%= if node_health.cpu_count && node_health.cpu_count > 0 do %>
                            <span title="CPUs">{node_health.cpu_count} CPU(s)</span>
                          <% end %>
                          <%= if node_health.total_memory > 0 do %>
                            <span title="Total RAM">
                              {format_bytes(node_health.total_memory)} RAM
                            </span>
                          <% end %>
                        </div>
                      <% else %>
                        <div class="text-sm text-base-content/50 italic">
                          <%= if node.status == "offline" do %>
                            Node offline - no health data available
                          <% else %>
                            Fetching health data...
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>

                <div class="card-actions justify-end mt-2">
                  <.link navigate={~p"/nodes"} class="btn btn-ghost btn-sm">
                    Manage Nodes <.icon name="hero-arrow-right" class="size-4" />
                  </.link>
                </div>
              <% end %>
            </div>
          </div>

          <%!-- Quick Actions --%>
          <div class="card bg-base-100 shadow-sm border border-base-300">
            <div class="card-body">
              <h2 class="card-title">
                <.icon name="hero-bolt" class="size-5" /> Quick Actions
              </h2>

              <%= if @can_write do %>
                <div class="space-y-2">
                  <.link
                    navigate={~p"/nodes/new"}
                    class="btn btn-outline btn-block justify-start gap-2"
                  >
                    <.icon name="hero-plus" class="size-4" /> Add Node
                  </.link>
                  <.link navigate={~p"/dns/new"} class="btn btn-outline btn-block justify-start gap-2">
                    <.icon name="hero-globe-alt" class="size-4" /> Add DNS Record
                  </.link>
                  <.link
                    navigate={~p"/routeros-users/new"}
                    class="btn btn-outline btn-block justify-start gap-2"
                  >
                    <.icon name="hero-user-plus" class="size-4" /> Add User
                  </.link>
                  <.link navigate={~p"/audit"} class="btn btn-outline btn-block justify-start gap-2">
                    <.icon name="hero-clipboard-document-list" class="size-4" /> View Audit Logs
                  </.link>
                </div>
              <% else %>
                <div class="alert alert-info text-sm">
                  <.icon name="hero-information-circle" class="size-4" />
                  <div>
                    <p class="font-semibold">Limited Access</p>
                    <p class="text-xs">You need operator or admin privileges to create resources.</p>
                  </div>
                </div>
                <div class="space-y-2 mt-2">
                  <.link navigate={~p"/nodes"} class="btn btn-outline btn-block justify-start gap-2">
                    <.icon name="hero-server" class="size-4" /> View Nodes
                  </.link>
                  <.link navigate={~p"/dns"} class="btn btn-outline btn-block justify-start gap-2">
                    <.icon name="hero-globe-alt" class="size-4" /> View DNS
                  </.link>
                  <.link
                    navigate={~p"/routeros-users"}
                    class="btn btn-outline btn-block justify-start gap-2"
                  >
                    <.icon name="hero-user-group" class="size-4" /> View Users
                  </.link>
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <%!-- Recent Activity --%>
        <div class="card bg-base-100 shadow-sm border border-base-300">
          <div class="card-body">
            <div class="flex items-center justify-between">
              <h2 class="card-title">
                <.icon name="hero-clock" class="size-5" /> Recent Activity
              </h2>
              <.link navigate={~p"/audit"} class="btn btn-ghost btn-sm">
                View All <.icon name="hero-arrow-right" class="size-4" />
              </.link>
            </div>

            <%= if @recent_logs == [] do %>
              <div class="text-center py-8 text-base-content/50">
                <.icon name="hero-inbox" class="size-12 mx-auto mb-2 opacity-50" />
                <p>No recent activity</p>
                <p class="text-sm">
                  Activity logs will appear here once you start managing your cluster.
                </p>
              </div>
            <% else %>
              <div class="space-y-2">
                <div
                  :for={log <- @recent_logs}
                  class="flex items-center gap-3 p-3 rounded-lg hover:bg-base-200/50 transition-colors"
                >
                  <div class={["rounded-full p-2", action_color(log.action)]}>
                    <.icon name={resource_icon(log.resource_type)} class="size-4" />
                  </div>
                  <div class="flex-1 min-w-0">
                    <div class="font-medium text-sm truncate">
                      {humanize_action(log.action)} {log.resource_type}
                      <span class="text-base-content/60">
                        {log.resource_id}
                      </span>
                    </div>
                    <div class="text-xs text-base-content/60">
                      {format_relative_time(log.inserted_at)}
                      <%= if node_name = get_in(log.details, ["node_name"]) do %>
                        · <span class="badge badge-ghost badge-xs">{node_name}</span>
                      <% end %>
                    </div>
                  </div>
                  <div class="text-right">
                    <%= if log.success do %>
                      <.icon name="hero-check-circle" class="size-4 text-success" />
                    <% else %>
                      <.icon name="hero-x-circle" class="size-4 text-error" />
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp action_color("create"), do: "bg-success/10 text-success"
  defp action_color("update"), do: "bg-info/10 text-info"
  defp action_color("delete"), do: "bg-error/10 text-error"
  defp action_color("add"), do: "bg-success/10 text-success"
  defp action_color("remove"), do: "bg-error/10 text-error"
  defp action_color(_), do: "bg-base-200 text-base-content"

  defp resource_icon("node"), do: "hero-server"
  defp resource_icon("wireguard_interface"), do: "hero-shield-check"
  defp resource_icon("gre_tunnel"), do: "hero-arrows-right-left"
  defp resource_icon("wireguard_peer"), do: "hero-users"
  defp resource_icon("ip_address"), do: "hero-globe-alt"
  defp resource_icon("dns_record"), do: "hero-globe-alt"
  defp resource_icon("routeros_user"), do: "hero-user"
  defp resource_icon(_), do: "hero-cube"

  defp humanize_action("create"), do: "Created"
  defp humanize_action("update"), do: "Updated"
  defp humanize_action("delete"), do: "Deleted"
  defp humanize_action("add"), do: "Added"
  defp humanize_action("remove"), do: "Removed"
  defp humanize_action(action), do: String.capitalize(to_string(action))

  defp format_relative_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "Just now"
      diff < 3600 -> "#{div(diff, 60)} min ago"
      diff < 86400 -> "#{div(diff, 3600)} hours ago"
      true -> Calendar.strftime(datetime, "%b %d, %Y")
    end
  end

  defp stat_card(assigns) do
    color_classes = %{
      "primary" => "bg-primary/10 text-primary",
      "success" => "bg-success/10 text-success",
      "info" => "bg-info/10 text-info",
      "warning" => "bg-warning/10 text-warning",
      "error" => "bg-error/10 text-error"
    }

    assigns =
      assign(
        assigns,
        :color_class,
        Map.get(color_classes, assigns.color, "bg-primary/10 text-primary")
      )

    ~H"""
    <div class="card bg-base-100 shadow-sm border border-base-300">
      <div class="card-body p-4">
        <div class="flex items-center gap-4">
          <div class={["rounded-lg p-3", @color_class]}>
            <.icon name={@icon} class="size-6" />
          </div>
          <div>
            <div class="text-2xl font-bold">{@value}</div>
            <div class="text-sm text-base-content/70">{@title}</div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp status_badge(assigns) do
    ~H"""
    <%= case @status do %>
      <% "online" -> %>
        <span class="badge badge-success badge-sm gap-1">
          <span class="w-2 h-2 rounded-full bg-current animate-pulse"></span> Online
        </span>
      <% "offline" -> %>
        <span class="badge badge-error badge-sm gap-1">
          <span class="w-2 h-2 rounded-full bg-current"></span> Offline
        </span>
      <% _ -> %>
        <span class="badge badge-ghost badge-sm gap-1">
          <span class="w-2 h-2 rounded-full bg-current"></span> Unknown
        </span>
    <% end %>
    """
  end

  # Health data helpers

  defp get_node_health(health_map, node_id) do
    case Map.get(health_map, node_id) do
      {_node, {:ok, health}} -> health
      _ -> nil
    end
  end

  defp cpu_color_class(load) when load >= 90, do: "progress-error"
  defp cpu_color_class(load) when load >= 70, do: "progress-warning"
  defp cpu_color_class(_load), do: "progress-success"

  defp memory_color_class(percent) when percent >= 90, do: "progress-error"
  defp memory_color_class(percent) when percent >= 70, do: "progress-warning"
  defp memory_color_class(_percent), do: "progress-info"

  defp memory_percent(%{total_memory: total, free_memory: free}) when total > 0 do
    used = total - free
    round(used / total * 100)
  end

  defp memory_percent(_), do: 0

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_bytes(bytes) when bytes < 1_073_741_824,
    do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_073_741_824, 2)} GB"
end
