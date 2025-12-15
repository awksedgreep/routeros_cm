defmodule RouterosCmWeb.DNSLive.Index do
  @moduledoc """
  LiveView for managing DNS records across the cluster.
  Shows a unified cluster view with records grouped by name.
  """
  use RouterosCmWeb, :live_view

  alias RouterosCm.DNS

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "DNS Records")
     |> assign(:can_write, can_write?(socket))
     |> assign(:filter_type, "all")
     |> assign(:cluster_records, [])
     |> assign(:loading, true)
     |> load_records()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:record, nil)
    |> assign(:form, nil)
    |> assign(:editing_name, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:record, %{})
    |> assign(:form, to_form(%{}, as: "record"))
    |> assign(:editing_name, nil)
  end

  defp apply_action(socket, :edit, %{"name" => name}) do
    # Find the record data from cluster_records
    record = Enum.find(socket.assigns.cluster_records, &(&1.name == name))

    if record do
      form_data = %{
        "name" => record.name,
        "type" => record.type,
        "address" => record.address,
        "ttl" => if(record.ttl == "default", do: "", else: record.ttl)
      }

      socket
      |> assign(:record, record)
      |> assign(:form, to_form(form_data, as: "record"))
      |> assign(:editing_name, name)
    else
      socket
      |> put_flash(:error, "Record not found")
      |> push_patch(to: ~p"/dns")
    end
  end

  @impl true
  def handle_event("refresh", _, socket) do
    {:noreply, load_records(socket)}
  end

  @impl true
  def handle_event("filter_type", %{"type" => type}, socket) do
    {:noreply, assign(socket, :filter_type, type)}
  end

  @impl true
  def handle_event("save", %{"record" => record_params}, socket) do
    if can_write?(socket) do
      save_record(socket, socket.assigns.live_action, record_params)
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to perform this action")}
    end
  end

  @impl true
  def handle_event("delete", %{"name" => name}, socket) do
    if can_write?(socket) do
      case DNS.delete_dns_record_by_name(socket.assigns.current_scope, name) do
        {:ok, _successes, []} ->
          {:noreply,
           socket
           |> load_records()
           |> put_flash(:info, "DNS record '#{name}' deleted from all nodes")}

        {:ok, successes, failures} ->
          {:noreply,
           socket
           |> load_records()
           |> put_flash(
             :warning,
             "Deleted from #{length(successes)} nodes, failed on #{length(failures)}"
           )}
      end
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to delete records")}
    end
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, push_patch(socket, to: ~p"/dns")}
  end

  defp save_record(socket, :new, record_params) do
    case DNS.create_dns_record(socket.assigns.current_scope, record_params, cluster_wide: true) do
      {:ok, successes, []} ->
        {:noreply,
         socket
         |> load_records()
         |> put_flash(:info, "DNS record created on #{length(successes)} node(s)")
         |> push_patch(to: ~p"/dns")}

      {:ok, successes, failures} ->
        {:noreply,
         socket
         |> load_records()
         |> put_flash(
           :warning,
           "Created on #{length(successes)} nodes, failed on #{length(failures)}"
         )
         |> push_patch(to: ~p"/dns")}
    end
  end

  defp save_record(socket, :edit, record_params) do
    original_name = socket.assigns.editing_name

    case DNS.update_dns_record_by_name(socket.assigns.current_scope, original_name, record_params) do
      {:ok, successes, []} ->
        {:noreply,
         socket
         |> load_records()
         |> put_flash(:info, "DNS record updated on #{length(successes)} node(s)")
         |> push_patch(to: ~p"/dns")}

      {:ok, successes, failures} ->
        {:noreply,
         socket
         |> load_records()
         |> put_flash(
           :warning,
           "Updated on #{length(successes)} nodes, failed on #{length(failures)}"
         )
         |> push_patch(to: ~p"/dns")}
    end
  end

  defp load_records(socket) do
    {:ok, results} = DNS.list_dns_records(socket.assigns.current_scope)

    # Group records by name across all nodes
    cluster_records = group_records_by_name(results)

    socket
    |> assign(:cluster_records, cluster_records)
    |> assign(:loading, false)
  end

  defp group_records_by_name(results) do
    results
    |> Enum.filter(&match?({:ok, _, _}, &1))
    |> Enum.flat_map(fn {:ok, node, records} ->
      Enum.map(records, fn record ->
        {record["name"], %{node: node, record: record}}
      end)
    end)
    |> Enum.group_by(fn {name, _} -> name end, fn {_, data} -> data end)
    |> Enum.map(fn {name, nodes_data} ->
      first = List.first(nodes_data)
      record = first.record
      record_type = record["type"] || if record["cname"], do: "CNAME", else: "A"

      nodes_info =
        Enum.map(nodes_data, fn data ->
          %{
            node: data.node,
            id: data.record[".id"],
            disabled: data.record["disabled"] == "true"
          }
        end)

      %{
        name: name,
        type: record_type,
        address: record["address"] || record["cname"] || "—",
        ttl: record["ttl"] || "default",
        comment: record["comment"],
        nodes: nodes_info,
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

  defp filter_records(records, "all"), do: records

  defp filter_records(records, type) do
    Enum.filter(records, fn record ->
      String.downcase(record.type) == String.downcase(type)
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <%!-- Header --%>
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold">DNS Records</h1>
            <p class="text-base-content/70">Manage static DNS records across the cluster</p>
          </div>
          <div class="flex gap-2">
            <button phx-click="refresh" class="btn btn-ghost btn-sm gap-2" disabled={@loading}>
              <.icon name="hero-arrow-path" class={["size-4", @loading && "animate-spin"]} /> Refresh
            </button>
            <.link :if={@can_write} patch={~p"/dns/new"} class="btn btn-primary btn-sm gap-2">
              <.icon name="hero-plus" class="size-4" /> Add Record
            </.link>
          </div>
        </div>

        <%!-- Filters --%>
        <div class="card bg-base-100 shadow-sm border border-base-300">
          <div class="card-body p-4">
            <div class="flex gap-4">
              <div class="form-control">
                <label class="label py-1">
                  <span class="label-text text-sm">Record Type</span>
                </label>
                <select
                  phx-change="filter_type"
                  name="type"
                  class="select select-sm select-bordered"
                  value={@filter_type}
                >
                  <option value="all">All Types</option>
                  <option value="A">A Records</option>
                  <option value="AAAA">AAAA Records</option>
                  <option value="CNAME">CNAME Records</option>
                  <option value="MX">MX Records</option>
                </select>
              </div>
            </div>
          </div>
        </div>

        <%= if @loading do %>
          <div class="flex items-center justify-center py-12">
            <span class="loading loading-spinner loading-lg"></span>
          </div>
        <% else %>
          <%= if @cluster_records == [] do %>
            <div class="text-center py-12 text-base-content/50">
              <.icon name="hero-globe-alt" class="size-12 mx-auto mb-3 opacity-50" />
              <p class="font-medium">No DNS records configured</p>
              <p class="text-sm">Add your first static DNS record to get started.</p>
            </div>
          <% else %>
            <div class="card bg-base-100 shadow-sm border border-base-300">
              <div class="card-body p-0">
                <div class="overflow-x-auto">
                  <table class="table table-sm">
                    <thead>
                      <tr>
                        <th>Name</th>
                        <th>Type</th>
                        <th>Address / Target</th>
                        <th>TTL</th>
                        <th>Nodes</th>
                        <th :if={@can_write} class="w-20">Actions</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr
                        :for={record <- filter_records(@cluster_records, @filter_type)}
                        class="hover:bg-base-200/50"
                      >
                        <td class="font-mono text-sm">{record.name}</td>
                        <td>
                          <span class={[
                            "badge badge-sm",
                            type_badge_class(record.type)
                          ]}>
                            {record.type}
                          </span>
                        </td>
                        <td class="font-mono text-sm">{record.address}</td>
                        <td class="text-sm">{record.ttl}</td>
                        <td>
                          <div class="flex gap-1 flex-wrap">
                            <%= for node_info <- record.nodes do %>
                              <div class="badge badge-outline badge-sm gap-1">
                                <div class={[
                                  "w-2 h-2 rounded-full",
                                  if(node_info.disabled, do: "bg-error", else: "bg-success")
                                ]}>
                                </div>
                                {node_info.node.name}
                              </div>
                            <% end %>
                          </div>
                        </td>
                        <td :if={@can_write}>
                          <div class="flex gap-1">
                            <.link
                              patch={~p"/dns/#{record.name}/edit"}
                              class="btn btn-ghost btn-xs btn-square"
                              title="Edit record"
                            >
                              <.icon name="hero-pencil-square" class="size-4" />
                            </.link>
                            <button
                              type="button"
                              phx-click="delete"
                              phx-value-name={record.name}
                              data-confirm={"Delete '#{record.name}' from ALL nodes in the cluster?"}
                              class="btn btn-ghost btn-xs btn-square text-error"
                              title="Delete from cluster"
                            >
                              <.icon name="hero-trash" class="size-4" />
                            </button>
                          </div>
                        </td>
                      </tr>
                    </tbody>
                  </table>

                  <div
                    :if={filter_records(@cluster_records, @filter_type) == []}
                    class="text-center py-8 text-base-content/50"
                  >
                    <p class="text-sm">No records match the current filter</p>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>

      <%!-- Modal for Add/Edit --%>
      <.modal
        :if={@live_action in [:new, :edit]}
        id="record-modal"
        show
        on_cancel={JS.patch(~p"/dns")}
      >
        <.record_form form={@form} mode={@live_action} />
      </.modal>
    </Layouts.app>
    """
  end

  defp type_badge_class("A"), do: "badge-primary"
  defp type_badge_class("AAAA"), do: "badge-secondary"
  defp type_badge_class("CNAME"), do: "badge-accent"
  defp type_badge_class("MX"), do: "badge-info"
  defp type_badge_class(_), do: "badge-ghost"

  defp record_form(assigns) do
    ~H"""
    <div>
      <h2 class="text-xl font-bold mb-4">
        {if @mode == :edit, do: "Edit DNS Record", else: "Add DNS Record"}
      </h2>

      <.form for={@form} id="record-form" phx-submit="save" class="space-y-4">
        <.input
          field={@form[:name]}
          label="Domain Name"
          placeholder="example.com"
          required
          readonly={@mode == :edit}
        />

        <div class="form-control">
          <label class="label">
            <span class="label-text">Record Type</span>
          </label>
          <select
            name="record[type]"
            class="select select-bordered"
            disabled={@mode == :edit}
          >
            <option value="A" selected={@form[:type].value == "A"}>A (IPv4)</option>
            <option value="AAAA" selected={@form[:type].value == "AAAA"}>AAAA (IPv6)</option>
            <option value="CNAME" selected={@form[:type].value == "CNAME"}>CNAME</option>
          </select>
          <input :if={@mode == :edit} type="hidden" name="record[type]" value={@form[:type].value} />
        </div>

        <.input field={@form[:address]} label="IP Address / Target" placeholder="192.168.1.1" />

        <.input field={@form[:ttl]} type="number" label="TTL (seconds)" placeholder="3600" />

        <div class="flex justify-end gap-2 pt-4">
          <.link patch={~p"/dns"} class="btn btn-ghost">
            Cancel
          </.link>
          <button
            type="submit"
            class="btn btn-primary"
            phx-disable-with={if @mode == :edit, do: "Updating...", else: "Creating..."}
          >
            <.icon name="hero-check" class="size-4" />
            {if @mode == :edit, do: "Update Record", else: "Create Record"}
          </button>
        </div>
      </.form>
    </div>
    """
  end
end
