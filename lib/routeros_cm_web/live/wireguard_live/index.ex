defmodule RouterosCmWeb.WireGuardLive.Index do
  @moduledoc """
  LiveView for managing WireGuard interfaces across the cluster.

  Displays interfaces grouped by name since cluster interfaces share the same
  private key across all nodes.
  """
  use RouterosCmWeb, :live_view

  alias RouterosCm.{Cluster, Tunnels}
  alias RouterosCm.WireGuard.Keys
  alias RouterosCmWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(30_000, self(), :refresh)
    end

    {:ok,
     socket
     |> assign(:page_title, "WireGuard Interfaces")
     |> assign(:loading, true)
     |> load_data()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "WireGuard Interfaces")
    |> assign(:modal, nil)
  end

  defp apply_action(socket, :new, _params) do
    form =
      to_form(
        %{
          "name" => "",
          "listen_port" => "",
          "private_key" => "",
          "mtu" => "1420",
          "comment" => ""
        },
        as: "interface"
      )

    socket
    |> assign(:page_title, "New WireGuard Interface")
    |> assign(:modal, :new_interface)
    |> assign(:form, form)
  end

  defp apply_action(socket, :assign_ip, %{"interface_name" => interface_name}) do
    form = to_form(%{"address" => ""}, as: "ip")

    socket
    |> assign(:page_title, "Assign IP - #{interface_name}")
    |> assign(:modal, :assign_ip)
    |> assign(:selected_interface, interface_name)
    |> assign(:ip_form, form)
  end

  @impl true
  def handle_event("delete", %{"interface-name" => interface_name}, socket) do
    if can_write?(socket) do
      case Tunnels.delete_wireguard_interface_cluster(socket.assigns.current_scope, interface_name) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Interface #{interface_name} deleted from cluster")
           |> load_data()}

        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(:error, "Failed to delete interface")
           |> load_data()}
      end
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to delete interfaces")}
    end
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, load_data(socket)}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("save", %{"interface" => params}, socket) do
    if can_write?(socket) do
      save_interface(socket, params)
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to create interfaces")}
    end
  end

  def handle_event("save_ip", %{"ip" => %{"address" => address}}, socket) do
    if can_write?(socket) do
      interface_name = socket.assigns.selected_interface

      case Tunnels.assign_wireguard_ip(
             socket.assigns.current_scope,
             interface_name,
             address
           ) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "IP #{address} assigned to #{interface_name} on all nodes")
           |> push_patch(to: ~p"/wireguard")
           |> load_data()}

        {:error, reason} ->
          {:noreply,
           socket
           |> put_flash(:error, "Failed to assign IP: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "You don't have permission")}
    end
  end

  def handle_event("copy_key", %{"key" => _key}, socket) do
    # The actual copy happens via JS, this just confirms
    {:noreply, put_flash(socket, :info, "Public key copied to clipboard")}
  end

  def handle_event("delete_ip", %{"interface" => interface_name, "address" => address}, socket) do
    if can_write?(socket) do
      case Tunnels.remove_wireguard_ip(socket.assigns.current_scope, interface_name, address) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "IP #{address} removed from #{interface_name}")
           |> load_data()}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to remove IP address")}
      end
    else
      {:noreply, put_flash(socket, :error, "You don't have permission")}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, load_data(socket)}
  end

  defp save_interface(socket, params) do
    # Auto-generate private key if not provided
    private_key =
      case params["private_key"] do
        nil -> Keys.generate_private_key()
        "" -> Keys.generate_private_key()
        key -> key
      end

    attrs =
      %{
        "name" => params["name"],
        "listen-port" => params["listen_port"],
        "private-key" => private_key,
        "mtu" => params["mtu"],
        "comment" => params["comment"]
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Map.new()

    # Deploy to all active nodes
    node_ids = Enum.map(Cluster.list_active_nodes(), & &1.id)

    case Tunnels.create_wireguard_interface(socket.assigns.current_scope, attrs, nodes: node_ids) do
      {:ok, results} ->
        node_names = Enum.map_join(results, ", ", fn {node, _} -> node.name end)

        {:noreply,
         socket
         |> put_flash(:info, "Interface created on: #{node_names}")
         |> push_patch(to: ~p"/wireguard")
         |> load_data()}

      {:error, %{successes: successes, failures: failures}} ->
        success_names = Enum.map_join(successes, ", ", fn {node, _} -> node.name end)
        failure_names = Enum.map_join(failures, ", ", fn {node, _} -> node.name end)

        {:noreply,
         socket
         |> put_flash(:warning, "Created on #{success_names}, failed on: #{failure_names}")
         |> push_patch(to: ~p"/wireguard")
         |> load_data()}
    end
  end

  defp load_data(socket) do
    raw_interfaces = Tunnels.list_wireguard_interfaces(socket.assigns.current_scope)
    addresses = Tunnels.list_addresses(socket.assigns.current_scope)

    # Build addresses lookup
    addresses_by_node_interface = build_addresses_map(addresses)

    # Group interfaces by name for cluster view
    cluster_interfaces = group_interfaces_by_name(raw_interfaces, addresses_by_node_interface)

    socket
    |> assign(:cluster_interfaces, cluster_interfaces)
    |> assign(:loading, false)
  end

  defp build_addresses_map(addresses) do
    addresses
    |> Enum.map(fn {node, result} ->
      case result do
        {:ok, addr_list} ->
          by_interface = Enum.group_by(addr_list, fn addr -> addr["interface"] end)
          {node.id, by_interface}

        {:error, _} ->
          {node.id, %{}}
      end
    end)
    |> Map.new()
  end

  defp group_interfaces_by_name(raw_interfaces, addresses_map) do
    raw_interfaces
    |> Enum.flat_map(fn {node, result} ->
      case result do
        {:ok, interfaces} ->
          Enum.map(interfaces, fn iface ->
            addrs = get_in(addresses_map, [node.id, iface["name"]]) || []
            {iface["name"], %{node: node, interface: iface, addresses: addrs}}
          end)

        {:error, _} ->
          []
      end
    end)
    |> Enum.group_by(fn {name, _} -> name end, fn {_, data} -> data end)
    |> Enum.map(fn {name, nodes_data} ->
      # All nodes should have same public key, take first
      first = List.first(nodes_data)
      public_key = first.interface["public-key"]
      listen_port = first.interface["listen-port"]

      # Collect node statuses and addresses
      nodes_info =
        Enum.map(nodes_data, fn data ->
          %{
            node: data.node,
            status: if(data.interface["disabled"] == "true", do: :disabled, else: :active),
            addresses: data.addresses
          }
        end)

      # Get unique addresses across all nodes
      all_addresses =
        nodes_data
        |> Enum.flat_map(& &1.addresses)
        |> Enum.map(& &1["address"])
        |> Enum.uniq()

      %{
        name: name,
        public_key: public_key,
        listen_port: listen_port,
        nodes: nodes_info,
        addresses: all_addresses,
        node_count: length(nodes_data)
      }
    end)
    |> Enum.sort_by(& &1.name)
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
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-3xl font-bold">WireGuard Interfaces</h1>
            <p class="text-sm text-base-content/70 mt-1">
              Manage WireGuard VPN interfaces across your cluster
            </p>
          </div>
          <div class="flex gap-2">
            <button phx-click="refresh" class="btn btn-ghost btn-sm gap-2" disabled={@loading}>
              <.icon name="hero-arrow-path" class={["w-4 h-4", @loading && "animate-spin"]} /> Refresh
            </button>
            <%= if @current_scope.user do %>
              <.link patch={~p"/wireguard/new"} class="btn btn-primary btn-sm gap-2">
                <.icon name="hero-plus" class="w-4 h-4" /> New Interface
              </.link>
            <% end %>
          </div>
        </div>

        <%= if @loading do %>
          <div class="flex items-center justify-center py-12">
            <span class="loading loading-spinner loading-lg"></span>
          </div>
        <% else %>
          <%= if @cluster_interfaces == [] do %>
            <div class="card bg-base-100 shadow-sm border border-base-300">
              <div class="card-body text-center py-12">
                <.icon name="hero-shield-check" class="w-16 h-16 mx-auto text-base-content/30" />
                <h3 class="text-lg font-semibold mt-4">No WireGuard interfaces</h3>
                <p class="text-sm text-base-content/60">
                  Create a WireGuard interface to get started with VPN tunnels
                </p>
                <%= if @current_scope.user do %>
                  <div class="mt-4">
                    <.link patch={~p"/wireguard/new"} class="btn btn-primary btn-sm">
                      Create Interface
                    </.link>
                  </div>
                <% end %>
              </div>
            </div>
          <% else %>
            <div class="space-y-4">
              <%= for iface <- @cluster_interfaces do %>
                <div class="card bg-base-100 shadow-sm border border-base-300">
                  <div class="card-body">
                    <%!-- Header --%>
                    <div class="flex items-start justify-between">
                      <div class="flex items-center gap-3">
                        <div class="avatar placeholder">
                          <div class="bg-primary text-primary-content rounded-lg w-12">
                            <.icon name="hero-shield-check" class="w-6 h-6" />
                          </div>
                        </div>
                        <div>
                          <h2 class="text-xl font-bold font-mono">{iface.name}</h2>
                          <p class="text-sm text-base-content/60">
                            Port: {iface.listen_port || "auto"} •
                            {iface.node_count} node(s)
                          </p>
                        </div>
                      </div>
                      <%= if @current_scope.user do %>
                        <div class="flex gap-2">
                          <.link
                            patch={~p"/wireguard/#{iface.name}/assign-ip"}
                            class="btn btn-sm btn-ghost gap-1"
                            title="Assign IP address"
                          >
                            <.icon name="hero-globe-alt" class="w-4 h-4" /> Assign IP
                          </.link>
                          <.link
                            navigate={~p"/wireguard/#{iface.name}/peers"}
                            class="btn btn-sm btn-outline btn-primary gap-1"
                          >
                            <.icon name="hero-user-group" class="w-4 h-4" /> Manage Peers
                          </.link>
                          <button
                            phx-click="delete"
                            phx-value-interface-name={iface.name}
                            data-confirm="Delete #{iface.name} from ALL nodes in the cluster?"
                            class="btn btn-sm btn-ghost text-error"
                            title="Delete from cluster"
                          >
                            <.icon name="hero-trash" class="w-4 h-4" />
                          </button>
                        </div>
                      <% end %>
                    </div>

                    <div class="divider my-2"></div>

                    <%!-- Public Key with Copy --%>
                    <div class="flex items-center gap-2 mb-3">
                      <span class="text-sm font-medium text-base-content/70">Public Key:</span>
                      <code
                        class="flex-1 text-xs bg-base-200 px-3 py-2 rounded font-mono truncate"
                        id={"pubkey-#{iface.name}"}
                      >
                        {iface.public_key}
                      </code>
                      <button
                        type="button"
                        class="btn btn-sm btn-ghost"
                        title="Copy public key"
                        onclick={"navigator.clipboard.writeText('#{iface.public_key}').then(() => { this.classList.add('btn-success'); setTimeout(() => this.classList.remove('btn-success'), 1000); })"}
                      >
                        <.icon name="hero-clipboard-document" class="w-4 h-4" />
                      </button>
                    </div>

                    <%!-- IP Address --%>
                    <div class="flex items-center gap-2 mb-3">
                      <span class="text-sm font-medium text-base-content/70">IP Address:</span>
                      <%= if iface.addresses != [] do %>
                        <div class="flex gap-2 items-center flex-wrap">
                          <%= for addr <- iface.addresses do %>
                            <div class="badge badge-lg font-mono gap-1 pr-1">
                              {addr}
                              <%= if @current_scope.user do %>
                                <button
                                  type="button"
                                  phx-click="delete_ip"
                                  phx-value-interface={iface.name}
                                  phx-value-address={addr}
                                  data-confirm={"Remove #{addr} from #{iface.name} on all nodes?"}
                                  class="btn btn-ghost btn-xs btn-circle hover:btn-error"
                                  title="Remove IP"
                                >
                                  <.icon name="hero-x-mark" class="w-3 h-3" />
                                </button>
                              <% end %>
                            </div>
                          <% end %>
                          <span class="text-xs text-base-content/50">
                            (on {iface.node_count} node(s))
                          </span>
                        </div>
                      <% else %>
                        <span class="text-base-content/40 text-sm">No IP assigned</span>
                        <%= if @current_scope.user do %>
                          <.link
                            patch={~p"/wireguard/#{iface.name}/assign-ip"}
                            class="btn btn-xs btn-ghost text-primary"
                          >
                            Assign now
                          </.link>
                        <% end %>
                      <% end %>
                    </div>

                    <%!-- Node Status --%>
                    <div class="flex items-center gap-2">
                      <span class="text-sm font-medium text-base-content/70">Nodes:</span>
                      <div class="flex gap-2 flex-wrap">
                        <%= for node_info <- iface.nodes do %>
                          <div class="badge badge-outline gap-1">
                            <div class={[
                              "w-2 h-2 rounded-full",
                              if(node_info.status == :active, do: "bg-success", else: "bg-error")
                            ]}>
                            </div>
                            {node_info.node.name}
                          </div>
                        <% end %>
                      </div>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        <% end %>
      </div>

      <%!-- New Interface Modal --%>
      <.modal
        :if={@modal == :new_interface}
        id="interface-modal"
        show
        on_cancel={JS.patch(~p"/wireguard")}
      >
        <h2 class="text-xl font-bold mb-4">New WireGuard Interface</h2>
        <p class="text-sm text-base-content/60 mb-4">
          Creates the interface on all active nodes with the same private key.
        </p>

        <.form for={@form} id="interface-form" phx-submit="save" phx-change="validate" class="space-y-4">
          <.input field={@form[:name]} type="text" label="Interface Name" placeholder="wg0" required />

          <.input
            field={@form[:listen_port]}
            type="number"
            label="Listen Port"
            placeholder="51820 (optional)"
          />

          <.input
            field={@form[:private_key]}
            type="text"
            label="Private Key"
            placeholder="Leave blank to auto-generate"
          />

          <.input field={@form[:mtu]} type="number" label="MTU" value="1420" />

          <.input field={@form[:comment]} type="text" label="Comment (optional)" />

          <div class="flex justify-end gap-2 pt-4">
            <.link patch={~p"/wireguard"} class="btn btn-ghost">Cancel</.link>
            <button type="submit" class="btn btn-primary">Create Interface</button>
          </div>
        </.form>
      </.modal>

      <%!-- Assign IP Modal --%>
      <.modal
        :if={@modal == :assign_ip}
        id="ip-modal"
        show
        on_cancel={JS.patch(~p"/wireguard")}
      >
        <h2 class="text-xl font-bold mb-4">Assign IP Address</h2>
        <p class="text-sm text-base-content/60 mb-4">
          Assigns this IP to <span class="font-mono font-bold">{@selected_interface}</span> on all nodes.
        </p>

        <.form for={@ip_form} id="ip-form" phx-submit="save_ip" class="space-y-4">
          <.input
            field={@ip_form[:address]}
            type="text"
            label="IP Address (CIDR)"
            placeholder="10.0.0.1/24"
            required
          />

          <div class="flex justify-end gap-2 pt-4">
            <.link patch={~p"/wireguard"} class="btn btn-ghost">Cancel</.link>
            <button type="submit" class="btn btn-primary">Assign IP</button>
          </div>
        </.form>
      </.modal>
    </Layouts.app>
    """
  end
end
