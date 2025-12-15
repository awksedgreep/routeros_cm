defmodule RouterosCmWeb.WireGuardLive.Peers do
  @moduledoc """
  LiveView for managing WireGuard peers across the cluster.

  Peers are managed at the interface level and deployed to all nodes.
  """
  use RouterosCmWeb, :live_view

  alias RouterosCm.{Cluster, Tunnels}
  alias RouterosCm.MikroTik.Client
  alias RouterosCmWeb.Layouts

  @impl true
  def mount(%{"interface_name" => interface_name}, _session, socket) do
    if connected?(socket) do
      Process.send_after(self(), :refresh, 10_000)
    end

    # Get interface info (public key, etc.) from first available node
    interface_info = get_interface_info(interface_name)

    {:ok,
     socket
     |> assign(:interface_name, interface_name)
     |> assign(:interface_info, interface_info)
     |> load_peers()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Peers - #{socket.assigns.interface_name}")
    |> assign(:modal, nil)
  end

  defp apply_action(socket, :new, _params) do
    form =
      to_form(
        %{
          "public_key" => "",
          "allowed_address" => "",
          "endpoint_address" => "",
          "endpoint_port" => "",
          "preshared_key" => "",
          "persistent_keepalive" => "",
          "comment" => ""
        },
        as: "peer"
      )

    socket
    |> assign(:page_title, "Add Peer - #{socket.assigns.interface_name}")
    |> assign(:modal, :new_peer)
    |> assign(:form, form)
    |> assign(:show_remote_commands, false)
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, 10_000)
    {:noreply, load_peers(socket)}
  end

  @impl true
  def handle_event("delete", %{"public_key" => public_key}, socket) do
    case Tunnels.delete_wireguard_peer_cluster(
           socket.assigns.current_scope,
           socket.assigns.interface_name,
           public_key
         ) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Peer removed from all nodes")
         |> load_peers()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete peer")}
    end
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, load_peers(socket)}
  end

  def handle_event("validate", %{"peer" => peer_params}, socket) do
    {:noreply, assign(socket, :form, to_form(peer_params, as: "peer"))}
  end

  def handle_event("toggle_remote_commands", _params, socket) do
    {:noreply, assign(socket, show_remote_commands: !socket.assigns.show_remote_commands)}
  end

  def handle_event("save", %{"peer" => peer_params}, socket) do
    attrs =
      peer_params
      |> Map.take([
        "public_key",
        "allowed_address",
        "endpoint_address",
        "endpoint_port",
        "preshared_key",
        "persistent_keepalive",
        "comment"
      ])
      |> Map.new(fn {k, v} -> {String.replace(k, "_", "-"), v} end)
      |> Enum.reject(fn {_k, v} -> v == "" or is_nil(v) end)
      |> Map.new()

    case Tunnels.create_wireguard_peer(
           socket.assigns.current_scope,
           socket.assigns.interface_name,
           attrs,
           cluster_wide: true
         ) do
      {:ok, _results} ->
        {:noreply,
         socket
         |> put_flash(:info, "Peer added to all nodes")
         |> push_patch(to: ~p"/wireguard/#{socket.assigns.interface_name}/peers")
         |> load_peers()}

      {:error, :no_nodes} ->
        {:noreply,
         socket
         |> put_flash(:error, "No active nodes available")
         |> assign(:form, to_form(peer_params, as: "peer"))}
    end
  end

  defp get_interface_info(interface_name) do
    case Cluster.list_active_nodes() do
      [node | _] ->
        case Client.list_wireguard_interfaces(node) do
          {:ok, interfaces} ->
            Enum.find(interfaces, &(&1["name"] == interface_name))

          _ ->
            nil
        end

      [] ->
        nil
    end
  end

  defp load_peers(socket) do
    case Tunnels.list_wireguard_peers(socket.assigns.current_scope, socket.assigns.interface_name) do
      {:ok, results} ->
        # Consolidate peers across nodes - group by public key
        peers =
          results
          |> Enum.flat_map(fn {_node, {:ok, peers}} -> peers end)
          |> Enum.uniq_by(& &1["public-key"])
          |> Enum.sort_by(& &1["public-key"])

        # Track which nodes have each peer
        peer_node_map =
          results
          |> Enum.flat_map(fn {node, {:ok, peers}} ->
            Enum.map(peers, fn peer -> {peer["public-key"], node.name} end)
          end)
          |> Enum.group_by(fn {key, _} -> key end, fn {_, node} -> node end)

        socket
        |> assign(:peers, peers)
        |> assign(:peer_node_map, peer_node_map)
        |> assign(:peers_empty?, peers == [])

      {:error, _reason} ->
        socket
        |> put_flash(:error, "Failed to load peers")
        |> assign(:peers, [])
        |> assign(:peer_node_map, %{})
        |> assign(:peers_empty?, true)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_scope={@current_scope} flash={@flash}>
      <div class="space-y-6">
        <%!-- Header --%>
        <div class="flex items-center gap-4">
          <.link navigate={~p"/wireguard"} class="btn btn-ghost btn-sm">
            <.icon name="hero-arrow-left" class="w-4 h-4" /> Back
          </.link>
          <div class="flex-1">
            <h1 class="text-3xl font-bold">WireGuard Peers</h1>
            <p class="text-base-content/60 mt-1">
              Interface: <span class="font-mono font-bold">{@interface_name}</span>
            </p>
          </div>
          <div class="flex gap-2">
            <button phx-click="refresh" class="btn btn-sm btn-ghost gap-2" title="Refresh peers">
              <.icon name="hero-arrow-path" class="w-4 h-4" /> Refresh
            </button>
            <%= if @current_scope.user do %>
              <.link
                patch={~p"/wireguard/#{@interface_name}/peers/new"}
                class="btn btn-sm btn-primary gap-2"
              >
                <.icon name="hero-plus" class="w-4 h-4" /> Add Peer
              </.link>
            <% end %>
          </div>
        </div>

        <%!-- Interface Info Card --%>
        <%= if @interface_info do %>
          <div class="card bg-base-200 border border-base-300">
            <div class="card-body py-4">
              <div class="flex items-center gap-2">
                <span class="text-sm font-medium text-base-content/70">Cluster Public Key:</span>
                <code class="flex-1 text-xs bg-base-100 px-3 py-2 rounded font-mono truncate">
                  {@interface_info["public-key"]}
                </code>
                <button
                  type="button"
                  class="btn btn-sm btn-ghost"
                  title="Copy public key"
                  onclick={"navigator.clipboard.writeText('#{@interface_info["public-key"]}').then(() => { this.classList.add('btn-success'); setTimeout(() => this.classList.remove('btn-success'), 1000); })"}
                >
                  <.icon name="hero-clipboard-document" class="w-4 h-4" />
                </button>
              </div>
              <p class="text-xs text-base-content/60 mt-1">
                Share this key with remote sites to allow them to connect
              </p>
            </div>
          </div>
        <% end %>

        <%!-- Peers List --%>
        <%= if @peers_empty? do %>
          <div class="card bg-base-100 shadow-sm border border-base-300">
            <div class="card-body items-center text-center py-12">
              <.icon name="hero-user-group" class="w-16 h-16 text-base-content/20" />
              <h2 class="card-title mt-4">No peers configured</h2>
              <p class="text-base-content/60">Add a peer to establish VPN connections</p>
              <%= if @current_scope.user do %>
                <.link
                  patch={~p"/wireguard/#{@interface_name}/peers/new"}
                  class="btn btn-primary mt-4"
                >
                  Add First Peer
                </.link>
              <% end %>
            </div>
          </div>
        <% else %>
          <div class="card bg-base-100 shadow-sm border border-base-300">
            <div class="card-body">
              <div class="overflow-x-auto">
                <table class="table">
                  <thead>
                    <tr>
                      <th>Public Key</th>
                      <th>Allowed IPs</th>
                      <th>Endpoint</th>
                      <th>Last Handshake</th>
                      <th>Transfer</th>
                      <th>Nodes</th>
                      <%= if @current_scope.user do %>
                        <th class="text-right">Actions</th>
                      <% end %>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for peer <- @peers do %>
                      <tr class="hover">
                        <td>
                          <div class="flex items-center gap-2">
                            <code class="text-xs" title={peer["public-key"]}>
                              {String.slice(peer["public-key"] || "", 0..15)}...
                            </code>
                            <button
                              type="button"
                              class="btn btn-xs btn-ghost"
                              onclick={"navigator.clipboard.writeText('#{peer["public-key"]}')"}
                            >
                              <.icon name="hero-clipboard-document" class="w-3 h-3" />
                            </button>
                          </div>
                        </td>
                        <td>
                          <span class="font-mono text-sm">
                            {peer["allowed-address"] || "-"}
                          </span>
                        </td>
                        <td>
                          <span class="font-mono text-sm">
                            <%= if peer["endpoint-address"] do %>
                              {peer["endpoint-address"]}:{peer["endpoint-port"] || ""}
                            <% else %>
                              -
                            <% end %>
                          </span>
                        </td>
                        <td>
                          <span class="text-sm text-base-content/60">
                            {format_handshake(peer["last-handshake"])}
                          </span>
                        </td>
                        <td>
                          <div class="flex flex-col text-xs">
                            <span>↓ {format_bytes(peer["rx"] || "0")}</span>
                            <span>↑ {format_bytes(peer["tx"] || "0")}</span>
                          </div>
                        </td>
                        <td>
                          <div class="flex gap-1">
                            <%= for node_name <- Map.get(@peer_node_map, peer["public-key"], []) do %>
                              <span class="badge badge-sm badge-outline">{node_name}</span>
                            <% end %>
                          </div>
                        </td>
                        <%= if @current_scope.user do %>
                          <td class="text-right">
                            <button
                              phx-click="delete"
                              phx-value-public_key={peer["public-key"]}
                              data-confirm="Remove this peer from all nodes?"
                              class="btn btn-xs btn-error btn-outline gap-1"
                            >
                              <.icon name="hero-trash" class="w-3 h-3" /> Delete
                            </button>
                          </td>
                        <% end %>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Add Peer Modal --%>
      <.modal
        :if={@modal == :new_peer}
        id="peer-modal"
        show
        on_cancel={JS.patch(~p"/wireguard/#{@interface_name}/peers")}
      >
        <h2 class="text-xl font-bold mb-2">Add Peer</h2>
        <p class="text-sm text-base-content/60 mb-4">
          This peer will be added to <span class="font-mono font-bold">{@interface_name}</span> on all
          nodes.
        </p>

        <.form
          for={@form}
          id="peer-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-4"
        >
          <.input
            field={@form[:public_key]}
            type="text"
            label="Public Key"
            placeholder="Base64 encoded public key"
            required
          />

          <.input
            field={@form[:allowed_address]}
            type="text"
            label="Allowed IPs"
            placeholder="10.0.0.2/32, 192.168.1.0/24"
            required
          />

          <div class="grid grid-cols-2 gap-4">
            <.input
              field={@form[:endpoint_address]}
              type="text"
              label="Endpoint Address"
              placeholder="peer.example.com (optional)"
            />
            <.input
              field={@form[:endpoint_port]}
              type="number"
              label="Endpoint Port"
              placeholder="51820"
            />
          </div>

          <.input
            field={@form[:preshared_key]}
            type="password"
            label="Preshared Key (optional)"
            placeholder="For additional security"
          />

          <.input
            field={@form[:persistent_keepalive]}
            type="number"
            label="Persistent Keepalive"
            placeholder="25 (seconds, optional)"
          />

          <.input
            field={@form[:comment]}
            type="text"
            label="Comment (optional)"
          />

          <%!-- Remote MikroTik Commands --%>
          <%= if @interface_info do %>
            <div class="divider text-sm">Remote Setup Helper</div>

            <label class="label cursor-pointer justify-start gap-3">
              <input
                type="checkbox"
                class="checkbox checkbox-sm"
                checked={@show_remote_commands}
                phx-click="toggle_remote_commands"
              />
              <span class="label-text text-sm">
                Show RouterOS commands for remote site
              </span>
            </label>

            <%= if @show_remote_commands do %>
              <div class="mockup-code text-xs">
                <pre data-prefix=">" class="text-warning"><code>/interface wireguard peers add \</code></pre>
                <pre data-prefix=" "><code>  interface={@interface_name} \</code></pre>
                <pre data-prefix=" "><code>  public-key="{@interface_info["public-key"]}" \</code></pre>
                <pre data-prefix=" "><code>  allowed-address=YOUR_CLUSTER_IP/32 \</code></pre>
                <%= if @interface_info["listen-port"] do %>
                  <pre data-prefix=" "><code>  endpoint-port={@interface_info["listen-port"]} \</code></pre>
                <% end %>
                <pre data-prefix=" "><code>  comment="Cluster peer"</code></pre>
              </div>
              <p class="text-xs text-base-content/60">
                Run on the remote MikroTik. Replace YOUR_CLUSTER_IP and add endpoint-address.
              </p>
            <% end %>
          <% end %>

          <div class="flex gap-2 justify-end pt-4">
            <.link
              patch={~p"/wireguard/#{@interface_name}/peers"}
              class="btn btn-ghost"
            >
              Cancel
            </.link>
            <button type="submit" class="btn btn-primary" phx-disable-with="Adding...">
              Add Peer
            </button>
          </div>
        </.form>
      </.modal>
    </Layouts.app>
    """
  end

  defp format_handshake(nil), do: "Never"
  defp format_handshake(""), do: "Never"
  defp format_handshake(time) when is_binary(time), do: time
  defp format_handshake(_), do: "-"

  defp format_bytes(bytes) when is_binary(bytes) do
    case Integer.parse(bytes) do
      {num, _} -> format_bytes(num)
      :error -> bytes
    end
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes) when bytes < 1_073_741_824, do: "#{Float.round(bytes / 1_048_576, 1)} MB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_073_741_824, 1)} GB"
end
