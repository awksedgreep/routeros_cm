defmodule RouterosCmWeb.GRELive.Index do
  @moduledoc """
  LiveView for managing GRE tunnels across the cluster.
  Shows a unified cluster view with tunnels grouped by name.
  """
  use RouterosCmWeb, :live_view

  alias RouterosCm.{Cluster, Tunnels}
  alias RouterosCmWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(30_000, self(), :refresh)
    end

    {:ok,
     socket
     |> assign(:page_title, "GRE Tunnels")
     |> assign(:loading, true)
     |> assign(:cluster_tunnels, [])
     |> load_data()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "GRE Tunnels")
    |> assign(:form, nil)
    |> assign(:selected_interface, nil)
  end

  defp apply_action(socket, :new, _params) do
    nodes = Cluster.list_active_nodes()

    form =
      to_form(
        %{
          "name" => "",
          "local_address" => "",
          "remote_address" => "",
          "mtu" => "1476",
          "ipsec_secret" => "",
          "comment" => "",
          "deploy_to" => "all"
        },
        as: "tunnel"
      )

    socket
    |> assign(:page_title, "New GRE Tunnel")
    |> assign(:form, form)
    |> assign(:available_nodes, nodes)
  end

  defp apply_action(socket, :assign_ip, %{"interface_name" => interface_name}) do
    form = to_form(%{"address" => ""}, as: "ip")

    socket
    |> assign(:page_title, "Assign IP - #{interface_name}")
    |> assign(:form, nil)
    |> assign(:selected_interface, interface_name)
    |> assign(:ip_form, form)
  end

  @impl true
  def handle_event("delete", %{"name" => name}, socket) do
    if can_write?(socket) do
      case Tunnels.delete_gre_interface_by_name(socket.assigns.current_scope, name) do
        {:ok, _successes, []} ->
          {:noreply,
           socket
           |> put_flash(:info, "GRE tunnel '#{name}' deleted from all nodes")
           |> load_data()}

        {:ok, successes, failures} ->
          {:noreply,
           socket
           |> put_flash(
             :warning,
             "Deleted from #{length(successes)} nodes, failed on #{length(failures)}"
           )
           |> load_data()}
      end
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to delete tunnels")}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("save", %{"tunnel" => params}, socket) do
    if can_write?(socket) do
      save_tunnel(socket, params)
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to create tunnels")}
    end
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, push_patch(socket, to: ~p"/gre")}
  end

  @impl true
  def handle_event("save_ip", %{"ip" => %{"address" => address}}, socket) do
    if can_write?(socket) do
      interface_name = socket.assigns.selected_interface

      case Tunnels.assign_gre_ip(socket.assigns.current_scope, interface_name, address) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "IP #{address} assigned to #{interface_name} on all nodes")
           |> push_patch(to: ~p"/gre")
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

  @impl true
  def handle_event("delete_ip", %{"interface" => interface_name, "address" => address}, socket) do
    if can_write?(socket) do
      case Tunnels.remove_gre_ip(socket.assigns.current_scope, interface_name, address) do
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

  defp save_tunnel(socket, params) do
    deploy_to = Map.get(params, "deploy_to", "all")

    node_ids =
      case deploy_to do
        "all" -> Enum.map(Cluster.list_active_nodes(), & &1.id)
        node_id when is_binary(node_id) -> [String.to_integer(node_id)]
      end

    attrs =
      %{
        "name" => params["name"],
        "local-address" => params["local_address"],
        "remote-address" => params["remote_address"],
        "mtu" => params["mtu"] || "1476",
        "comment" => params["comment"] || ""
      }
      |> maybe_add_ipsec_secret(params["ipsec_secret"])

    case Tunnels.create_gre_interface(socket.assigns.current_scope, attrs, nodes: node_ids) do
      {:ok, results} ->
        node_names = Enum.map_join(results, ", ", fn {node, _} -> node.name end)

        {:noreply,
         socket
         |> put_flash(:info, "GRE tunnel created on: #{node_names}")
         |> push_patch(to: ~p"/gre")
         |> load_data()}

      {:error, %{successes: [], failures: failures}} ->
        error_details =
          failures
          |> Enum.map(fn {node, {:error, err}} ->
            error_msg = extract_error_message(err)
            "#{node.name}: #{error_msg}"
          end)
          |> Enum.join("; ")

        {:noreply,
         socket
         |> put_flash(:error, "Failed to create GRE tunnel: #{error_details}")
         |> push_patch(to: ~p"/gre")
         |> load_data()}

      {:error, %{successes: successes, failures: failures}} ->
        success_names = Enum.map_join(successes, ", ", fn {node, _} -> node.name end)

        failure_details =
          failures
          |> Enum.map(fn {node, {:error, err}} ->
            error_msg = extract_error_message(err)
            "#{node.name}: #{error_msg}"
          end)
          |> Enum.join("; ")

        {:noreply,
         socket
         |> put_flash(
           :warning,
           "Created on #{success_names}, but failed on: #{failure_details}"
         )
         |> push_patch(to: ~p"/gre")
         |> load_data()}
    end
  end

  defp load_data(socket) do
    raw_interfaces = Tunnels.list_gre_interfaces(socket.assigns.current_scope)
    addresses = Tunnels.list_addresses(socket.assigns.current_scope)

    # Build addresses lookup
    addresses_map = build_addresses_map(addresses)

    # Group interfaces by name for cluster view
    cluster_tunnels = group_tunnels_by_name(raw_interfaces, addresses_map)

    socket
    |> assign(:cluster_tunnels, cluster_tunnels)
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

  defp group_tunnels_by_name(raw_interfaces, addresses_map) do
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
      first = List.first(nodes_data)
      local_addr = first.interface["local-address"]
      remote_addr = first.interface["remote-address"]
      mtu = first.interface["mtu"]
      comment = first.interface["comment"]

      # Collect node statuses and addresses
      nodes_info =
        Enum.map(nodes_data, fn data ->
          %{
            node: data.node,
            id: data.interface[".id"],
            status: if(data.interface["disabled"] == "true", do: :disabled, else: :active),
            running: data.interface["running"] == "true",
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
        local_address: local_addr,
        remote_address: remote_addr,
        mtu: mtu,
        comment: comment,
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
            <h1 class="text-2xl font-bold">GRE Tunnels</h1>
            <p class="text-base-content/70">
              Manage Generic Routing Encapsulation tunnels across the cluster
            </p>
          </div>
          <div class="flex gap-2">
            <button phx-click="refresh" class="btn btn-ghost btn-sm gap-2" disabled={@loading}>
              <.icon name="hero-arrow-path" class={["w-4 h-4", @loading && "animate-spin"]} /> Refresh
            </button>
            <%= if @current_scope.user do %>
              <.link patch={~p"/gre/new"} class="btn btn-primary btn-sm gap-2">
                <.icon name="hero-plus" class="w-4 h-4" /> New GRE Tunnel
              </.link>
            <% end %>
          </div>
        </div>

        <%= if @loading do %>
          <div class="flex items-center justify-center py-12">
            <span class="loading loading-spinner loading-lg"></span>
          </div>
        <% else %>
          <%= if @cluster_tunnels == [] do %>
            <div class="text-center py-12 text-base-content/50">
              <.icon name="hero-arrows-right-left" class="size-12 mx-auto mb-3 opacity-50" />
              <p class="font-medium">No GRE tunnels configured</p>
              <p class="text-sm">Create your first GRE tunnel to get started.</p>
            </div>
          <% else %>
            <div class="card bg-base-100 shadow-sm border border-base-300">
              <div class="card-body p-0">
                <div class="overflow-x-auto">
                  <table class="table table-sm">
                    <thead>
                      <tr>
                        <th>Name</th>
                        <th>Local Address</th>
                        <th>Remote Address</th>
                        <th>Tunnel IPs</th>
                        <th>Nodes</th>
                        <th :if={@current_scope.user} class="w-24">Actions</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr :for={tunnel <- @cluster_tunnels} class="hover:bg-base-200/50">
                        <td>
                          <div class="flex items-center gap-2">
                            <.icon name="hero-arrows-right-left" class="w-4 h-4 text-secondary" />
                            <span class="font-mono font-medium">{tunnel.name}</span>
                          </div>
                        </td>
                        <td class="font-mono text-sm">{tunnel.local_address || "-"}</td>
                        <td class="font-mono text-sm">{tunnel.remote_address || "-"}</td>
                        <td>
                          <%= if tunnel.addresses != [] do %>
                            <div class="flex flex-wrap gap-1">
                              <%= for addr <- tunnel.addresses do %>
                                <div class="badge badge-sm font-mono gap-1 pr-1">
                                  {addr}
                                  <%= if @current_scope.user do %>
                                    <button
                                      type="button"
                                      phx-click="delete_ip"
                                      phx-value-interface={tunnel.name}
                                      phx-value-address={addr}
                                      data-confirm={"Remove #{addr} from #{tunnel.name} on all nodes?"}
                                      class="btn btn-ghost btn-xs btn-circle hover:btn-error"
                                      title="Remove IP"
                                    >
                                      <.icon name="hero-x-mark" class="w-2 h-2" />
                                    </button>
                                  <% end %>
                                </div>
                              <% end %>
                            </div>
                          <% else %>
                            <span class="text-base-content/40 text-xs">No IP assigned</span>
                          <% end %>
                        </td>
                        <td>
                          <div class="flex gap-1 flex-wrap">
                            <%= for node_info <- tunnel.nodes do %>
                              <div class="badge badge-outline badge-sm gap-1">
                                <div class={[
                                  "w-2 h-2 rounded-full",
                                  if(node_info.status == :disabled || !node_info.running,
                                    do: "bg-error",
                                    else: "bg-success"
                                  )
                                ]}>
                                </div>
                                {node_info.node.name}
                              </div>
                            <% end %>
                          </div>
                        </td>
                        <td :if={@current_scope.user}>
                          <div class="flex gap-1">
                            <.link
                              patch={~p"/gre/#{tunnel.name}/assign-ip"}
                              class="btn btn-ghost btn-xs btn-square"
                              title="Assign IP address"
                            >
                              <.icon name="hero-globe-alt" class="w-4 h-4" />
                            </.link>
                            <button
                              type="button"
                              phx-click="delete"
                              phx-value-name={tunnel.name}
                              data-confirm={"Delete '#{tunnel.name}' from ALL nodes in the cluster?"}
                              class="btn btn-ghost btn-xs btn-square text-error"
                              title="Delete from cluster"
                            >
                              <.icon name="hero-trash" class="w-4 h-4" />
                            </button>
                          </div>
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>

      <%!-- New GRE Tunnel Modal --%>
      <.modal :if={@live_action == :new} id="gre-modal" show on_cancel={JS.patch(~p"/gre")}>
        <h2 class="text-xl font-bold mb-4">New GRE Tunnel</h2>

        <.form for={@form} id="gre-form" phx-submit="save" class="space-y-4">
          <.input field={@form[:name]} type="text" label="Tunnel Name" required />

          <.input
            field={@form[:local_address]}
            type="text"
            label="Local Address"
            required
            placeholder="e.g., 10.0.0.1"
          />

          <.input
            field={@form[:remote_address]}
            type="text"
            label="Remote Address"
            required
            placeholder="e.g., 10.0.0.2"
          />

          <.input field={@form[:mtu]} type="text" label="MTU" value="1476" placeholder="1476" />

          <.input
            field={@form[:ipsec_secret]}
            type="password"
            label="IPsec Secret (optional)"
            placeholder="Leave empty for no encryption"
          />

          <.input field={@form[:comment]} type="text" label="Comment (optional)" />

          <div class="form-control">
            <label class="label">
              <span class="label-text">Deploy To</span>
            </label>
            <select name="tunnel[deploy_to]" class="select select-bordered">
              <option value="all">All Active Nodes</option>
              <option :for={node <- @available_nodes} value={node.id}>{node.name}</option>
            </select>
          </div>

          <div class="alert alert-info">
            <.icon name="hero-information-circle" class="w-5 h-5" />
            <div class="text-sm">
              <p class="font-semibold">GRE Tunnels</p>
              <p>
                GRE (Generic Routing Encapsulation) creates point-to-point tunnels between RouterOS devices for routing traffic.
              </p>
            </div>
          </div>

          <div class="flex justify-end gap-2 pt-4">
            <.link patch={~p"/gre"} class="btn btn-ghost">
              Cancel
            </.link>
            <button type="submit" class="btn btn-primary">
              Create Tunnel
            </button>
          </div>
        </.form>
      </.modal>

      <%!-- Assign IP Modal --%>
      <.modal
        :if={@live_action == :assign_ip}
        id="ip-modal"
        show
        on_cancel={JS.patch(~p"/gre")}
      >
        <h2 class="text-xl font-bold mb-4">Assign IP Address</h2>
        <p class="text-sm text-base-content/60 mb-4">
          Assigns this IP to <span class="font-mono font-bold">{@selected_interface}</span>
          on all nodes.
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
            <.link patch={~p"/gre"} class="btn btn-ghost">Cancel</.link>
            <button type="submit" class="btn btn-primary">Assign IP</button>
          </div>
        </.form>
      </.modal>
    </Layouts.app>
    """
  end

  defp extract_error_message(%{message: msg}) when is_binary(msg), do: msg
  defp extract_error_message(%{details: details}) when is_binary(details), do: details
  defp extract_error_message(err), do: inspect(err)

  defp maybe_add_ipsec_secret(attrs, nil), do: attrs
  defp maybe_add_ipsec_secret(attrs, ""), do: attrs

  defp maybe_add_ipsec_secret(attrs, secret) do
    # MikroTik doesn't support fast-path with IPsec, so disable it
    attrs
    |> Map.put("ipsec-secret", secret)
    |> Map.put("allow-fast-path", "false")
  end
end
