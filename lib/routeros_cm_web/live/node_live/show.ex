defmodule RouterosCmWeb.NodeLive.Show do
  @moduledoc """
  LiveView for showing detailed information about a single node.
  """
  use RouterosCmWeb, :live_view

  alias RouterosCm.Cluster

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    node = Cluster.get_node!(id)

    {:noreply,
     socket
     |> assign(:page_title, "Node: #{node.name}")
     |> assign(:node, node)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <%!-- Header --%>
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold">{@node.name}</h1>
            <p class="text-base-content/70">Node details and information</p>
          </div>
          <.link navigate={~p"/nodes"} class="btn btn-ghost gap-2">
            <.icon name="hero-arrow-left" class="size-4" /> Back to Nodes
          </.link>
        </div>

        <%!-- Node Details --%>
        <div class="card bg-base-100 shadow-sm border border-base-300">
          <div class="card-body">
            <h2 class="card-title">Connection Information</h2>
            <div class="grid grid-cols-2 gap-4">
              <div>
                <div class="text-sm text-base-content/70">Host</div>
                <div class="font-mono">{@node.host}</div>
              </div>
              <div>
                <div class="text-sm text-base-content/70">Port</div>
                <div class="font-mono">{@node.port}</div>
              </div>
              <div>
                <div class="text-sm text-base-content/70">Status</div>
                <div>
                  <.status_badge status={@node.status} />
                </div>
              </div>
              <div>
                <div class="text-sm text-base-content/70">Last Seen</div>
                <div>{format_last_seen(@node.last_seen_at)}</div>
              </div>
            </div>
          </div>
        </div>

        <%!-- Tunnels (placeholder for future implementation) --%>
        <div class="card bg-base-100 shadow-sm border border-base-300">
          <div class="card-body">
            <h2 class="card-title">Tunnels</h2>
            <p class="text-base-content/70">Tunnel management coming soon...</p>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp status_badge(assigns) do
    ~H"""
    <%= cond do %>
      <% @status == "online" -> %>
        <span class="badge badge-success badge-sm gap-1">
          <span class="w-2 h-2 rounded-full bg-current animate-pulse"></span> Online
        </span>
      <% @status == "offline" -> %>
        <span class="badge badge-error badge-sm gap-1">
          <span class="w-2 h-2 rounded-full bg-current"></span> Offline
        </span>
      <% true -> %>
        <span class="badge badge-sm gap-1">
          <span class="w-2 h-2 rounded-full bg-current"></span> Unknown
        </span>
    <% end %>
    """
  end

  defp format_last_seen(nil), do: "Never"

  defp format_last_seen(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "Just now"
      diff < 3600 -> "#{div(diff, 60)} min ago"
      diff < 86400 -> "#{div(diff, 3600)} hours ago"
      true -> Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
    end
  end
end
