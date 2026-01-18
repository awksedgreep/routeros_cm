defmodule RouterosCmWeb.NodeLive.Index do
  @moduledoc """
  LiveView for managing CHR cluster nodes.
  """
  use RouterosCmWeb, :live_view

  alias RouterosCm.Audit
  alias RouterosCm.Cluster
  alias RouterosCm.Cluster.Node

  @routeros_setup_code """
  # Create API user with full access (change password!)
  /user add name=routeros-cm group=full password=secret

  # Verify www service is enabled (REST API uses HTTP)
  /ip service enable www
  """

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Nodes")
     |> assign(:can_write, can_write?(socket))
     |> assign(:routeros_setup_code, @routeros_setup_code)
     |> stream(:nodes, Cluster.list_nodes())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:node, nil)
    |> assign(:form, nil)
  end

  defp apply_action(socket, :new, _params) do
    node = %Node{}
    form = Cluster.change_node(node) |> to_form()

    socket
    |> assign(:node, node)
    |> assign(:form, form)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    node = Cluster.get_node!(id)
    form = Cluster.change_node(node) |> to_form()

    socket
    |> assign(:node, node)
    |> assign(:form, form)
  end

  @impl true
  def handle_event("validate", %{"node" => node_params}, socket) do
    form =
      socket.assigns.node
      |> Cluster.change_node(node_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  @impl true
  def handle_event("save", %{"node" => node_params}, socket) do
    if can_write?(socket) do
      save_node(socket, socket.assigns.live_action, node_params)
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to perform this action")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    if can_write?(socket) do
      node = Cluster.get_node!(id)
      {:ok, _} = Cluster.delete_node(socket.assigns.current_scope, node)
      Audit.log_node_action(:delete, node, audit_opts(socket))

      {:noreply,
       socket
       |> stream_delete(:nodes, node)
       |> put_flash(:info, "Node \"#{node.name}\" deleted successfully")}
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to delete nodes")}
    end
  end

  @impl true
  def handle_event("test_connection", %{"id" => id}, socket) do
    node = Cluster.get_node!(id)

    case Cluster.test_connection(node) do
      {:ok, _info} ->
        Cluster.touch_node(node)
        updated_node = Cluster.get_node!(id)

        {:noreply,
         socket
         |> stream_insert(:nodes, updated_node)
         |> put_flash(:info, "Successfully connected to \"#{node.name}\"")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Connection failed: #{reason}")}
    end
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, push_patch(socket, to: ~p"/nodes")}
  end

  defp save_node(socket, :new, node_params) do
    case Cluster.create_node(socket.assigns.current_scope, node_params) do
      {:ok, node} ->
        Audit.log_node_action(
          :create,
          node,
          audit_opts(socket, %{details: "Node added to cluster"})
        )

        {:noreply,
         socket
         |> stream_insert(:nodes, node, at: 0)
         |> put_flash(:info, "Node \"#{node.name}\" created successfully")
         |> push_patch(to: ~p"/nodes")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_node(socket, :edit, node_params) do
    case Cluster.update_node(socket.assigns.current_scope, socket.assigns.node, node_params) do
      {:ok, node} ->
        Audit.log_node_action(
          :update,
          node,
          audit_opts(socket, %{details: "Node configuration updated"})
        )

        {:noreply,
         socket
         |> stream_insert(:nodes, node)
         |> put_flash(:info, "Node \"#{node.name}\" updated successfully")
         |> push_patch(to: ~p"/nodes")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  # Build audit options with user info from current_scope
  defp audit_opts(socket, extra \\ %{}) do
    case socket.assigns[:current_scope] do
      %{user: user} when not is_nil(user) ->
        Map.merge(extra, %{user_id: user.id})

      _ ->
        extra
    end
  end

  # Check if current user can write (all authenticated users for now)
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
        <%!-- Header --%>
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold">Cluster Nodes</h1>
            <p class="text-base-content/70">Manage MikroTik RouterOS nodes in your cluster</p>
          </div>
          <.link :if={@can_write} patch={~p"/nodes/new"} class="btn btn-primary gap-2">
            <.icon name="hero-plus" class="size-4" /> Add Node
          </.link>
        </div>

        <%!-- Nodes Table --%>
        <div class="card bg-base-100 shadow-sm border border-base-300">
          <div class="card-body p-0">
            <div class="overflow-x-auto">
              <table class="table">
                <thead>
                  <tr>
                    <th>Name</th>
                    <th>Host</th>
                    <th>Port</th>
                    <th>Status</th>
                    <th>Last Seen</th>
                    <th class="w-32">Actions</th>
                  </tr>
                </thead>
                <tbody id="nodes" phx-update="stream">
                  <tr
                    :for={{dom_id, node} <- @streams.nodes}
                    id={dom_id}
                    class="hover:bg-base-200/50 transition-colors"
                  >
                    <td class="font-medium">{node.name}</td>
                    <td class="font-mono text-sm">{node.host}</td>
                    <td class="font-mono text-sm">{node.port}</td>
                    <td>
                      <.status_badge status={node.status} />
                    </td>
                    <td class="text-sm text-base-content/70">
                      {format_last_seen(node.last_seen_at)}
                    </td>
                    <td>
                      <div :if={@can_write} class="flex gap-1">
                        <button
                          type="button"
                          phx-click="test_connection"
                          phx-value-id={node.id}
                          class="btn btn-ghost btn-xs btn-square"
                          title="Test Connection"
                        >
                          <.icon name="hero-signal" class="size-4" />
                        </button>
                        <.link
                          patch={~p"/nodes/#{node.id}/edit"}
                          class="btn btn-ghost btn-xs btn-square"
                          title="Edit"
                        >
                          <.icon name="hero-pencil-square" class="size-4" />
                        </.link>
                        <button
                          type="button"
                          phx-click="delete"
                          phx-value-id={node.id}
                          data-confirm={"Are you sure you want to delete node \"#{node.name}\"?"}
                          class="btn btn-ghost btn-xs btn-square text-error"
                          title="Delete"
                        >
                          <.icon name="hero-trash" class="size-4" />
                        </button>
                      </div>
                      <span :if={!@can_write} class="text-base-content/30">—</span>
                    </td>
                  </tr>
                </tbody>
              </table>

              <div
                :if={@streams.nodes.inserts == []}
                class="text-center py-12 text-base-content/50"
              >
                <.icon name="hero-server" class="size-12 mx-auto mb-3 opacity-50" />
                <p class="font-medium">No nodes configured</p>
                <p class="text-sm">Add your first MikroTik RouterOS node to get started.</p>
              </div>
            </div>
          </div>
        </div>

        <%!-- RouterOS Setup Help --%>
        <details class="text-sm text-base-content/70">
          <summary class="cursor-pointer hover:text-base-content inline-flex items-center gap-1">
            <.icon name="hero-question-mark-circle" class="size-4" />
            How to create a RouterOS API user
          </summary>
          <div class="mt-3 p-4 bg-base-200 rounded-lg space-y-3">
            <p>Run these commands in your RouterOS terminal:</p>

            <pre class="bg-base-300 p-3 rounded text-xs overflow-x-auto"><code>{@routeros_setup_code}</code></pre>

            <p class="text-base-content/60">
              <strong>Important:</strong>
              Replace <code class="bg-base-300 px-1 rounded">secret</code>
              with a strong password.
            </p>
          </div>
        </details>
      </div>

      <%!-- Modal for Add/Edit --%>
      <.modal
        :if={@live_action in [:new, :edit]}
        id="node-modal"
        show
        on_cancel={JS.patch(~p"/nodes")}
      >
        <.node_form form={@form} action={@live_action} />
      </.modal>
    </Layouts.app>
    """
  end

  defp node_form(assigns) do
    ~H"""
    <div>
      <h2 class="text-xl font-bold mb-4">
        {if @action == :new, do: "Add New Node", else: "Edit Node"}
      </h2>

      <.form for={@form} id="node-form" phx-change="validate" phx-submit="save" class="space-y-4">
        <.input field={@form[:name]} label="Node Name" placeholder="e.g., router-primary-01" />

        <div class="grid grid-cols-2 gap-4">
          <.input field={@form[:host]} label="Host / IP Address" placeholder="192.168.1.1" />
          <.input field={@form[:port]} type="number" label="API Port" placeholder="80" />
        </div>
        <p class="text-sm text-base-content/60 -mt-2">
          <.icon name="hero-information-circle" class="w-4 h-4 inline" />
          REST API ports: 80 (HTTP) or 443 (HTTPS)
        </p>

        <div class="grid grid-cols-2 gap-4">
          <.input field={@form[:username]} label="Username" placeholder="admin" />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            placeholder="••••••••"
          />
        </div>
        <p class="text-sm text-base-content/60 -mt-2">
          <.icon name="hero-shield-check" class="w-4 h-4 inline" />
          Credentials are encrypted at rest using AES-256-GCM
        </p>

        <div class="flex justify-end gap-2 pt-4">
          <.link patch={~p"/nodes"} class="btn btn-ghost">
            Cancel
          </.link>
          <button type="submit" class="btn btn-primary" phx-disable-with="Saving...">
            <.icon name="hero-check" class="size-4" />
            {if @action == :new, do: "Add Node", else: "Save Changes"}
          </button>
        </div>
      </.form>
    </div>
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
