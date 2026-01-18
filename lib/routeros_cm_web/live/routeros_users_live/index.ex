defmodule RouterosCmWeb.RouterOSUsersLive.Index do
  @moduledoc """
  LiveView for managing RouterOS system users across the cluster.
  Shows a unified cluster view with users grouped by username.
  """
  use RouterosCmWeb, :live_view

  alias RouterosCm.{Cluster, RouterOSUsers}
  alias RouterosCmWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "RouterOS Users")
     |> assign(:cluster_users, [])
     |> assign(:loading, true)
     |> assign(:filter_group, "all")
     |> load_users()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "RouterOS Users")
    |> assign(:form, nil)
    |> assign(:editing_name, nil)
  end

  defp apply_action(socket, :new, _params) do
    nodes = Cluster.list_active_nodes()

    form =
      to_form(
        %{
          "name" => "",
          "password" => "",
          "group" => "full",
          "comment" => "",
          "deploy_to" => "all"
        },
        as: :user
      )

    socket
    |> assign(:page_title, "Add RouterOS User")
    |> assign(:form, form)
    |> assign(:available_nodes, nodes)
    |> assign(:editing_name, nil)
  end

  defp apply_action(socket, :edit, %{"name" => name}) do
    # Find the user data from cluster_users
    user = Enum.find(socket.assigns.cluster_users, &(&1.name == name))

    if user do
      form =
        to_form(
          %{
            "name" => user.name,
            "password" => "",
            "group" => user.group,
            "comment" => user.comment
          },
          as: :user
        )

      socket
      |> assign(:page_title, "Edit User - #{name}")
      |> assign(:form, form)
      |> assign(:editing_name, name)
    else
      socket
      |> put_flash(:error, "User not found")
      |> push_patch(to: ~p"/routeros-users")
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_users(socket)}
  end

  @impl true
  def handle_event("filter", %{"group" => group}, socket) do
    {:noreply, assign(socket, :filter_group, group)}
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    {:noreply, assign(socket, :form, to_form(user_params, as: :user))}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    if can_write?(socket) do
      save_user(socket, socket.assigns.live_action, user_params)
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to modify users")}
    end
  end

  @impl true
  def handle_event("delete", %{"name" => username}, socket) do
    if can_write?(socket) do
      case RouterOSUsers.delete_routeros_user_by_name(username, socket.assigns.current_scope) do
        {:ok, _successes, []} ->
          {:noreply,
           socket
           |> put_flash(:info, "User '#{username}' deleted from all nodes")
           |> load_users()}

        {:ok, successes, failures} ->
          {:noreply,
           socket
           |> put_flash(
             :warning,
             "Deleted from #{length(successes)} nodes, failed on #{length(failures)}"
           )
           |> load_users()}
      end
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to delete users")}
    end
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, push_patch(socket, to: ~p"/routeros-users")}
  end

  defp save_user(socket, :new, user_params) do
    deploy_to = Map.get(user_params, "deploy_to", "all")

    node_names =
      case deploy_to do
        "all" -> "all"
        node_name when is_binary(node_name) -> [node_name]
      end

    case RouterOSUsers.create_routeros_user(
           user_params,
           node_names,
           socket.assigns.current_scope
         ) do
      {:ok, successes, []} ->
        node_list = Enum.map_join(successes, ", ", & &1.name)

        {:noreply,
         socket
         |> put_flash(:info, "User created successfully on: #{node_list}")
         |> push_patch(to: ~p"/routeros-users")
         |> load_users()}

      {:ok, successes, failures} ->
        success_list = Enum.map_join(successes, ", ", & &1.name)

        failure_list =
          Enum.map_join(failures, ", ", fn
            {node, _error} -> node.name
            _ -> "unknown"
          end)

        {:noreply,
         socket
         |> put_flash(
           :warning,
           "User created on #{success_list}, but failed on: #{failure_list}"
         )
         |> push_patch(to: ~p"/routeros-users")
         |> load_users()}
    end
  end

  defp save_user(socket, :edit, user_params) do
    username = socket.assigns.editing_name

    case RouterOSUsers.update_routeros_user_by_name(
           username,
           user_params,
           socket.assigns.current_scope
         ) do
      {:ok, successes, []} ->
        {:noreply,
         socket
         |> put_flash(:info, "User updated on #{length(successes)} node(s)")
         |> push_patch(to: ~p"/routeros-users")
         |> load_users()}

      {:ok, successes, failures} ->
        {:noreply,
         socket
         |> put_flash(
           :warning,
           "Updated on #{length(successes)} nodes, failed on #{length(failures)}"
         )
         |> push_patch(to: ~p"/routeros-users")
         |> load_users()}
    end
  end

  defp load_users(socket) do
    case RouterOSUsers.list_routeros_users(current_scope: socket.assigns.current_scope) do
      {:ok, results} ->
        cluster_users = group_users_by_name(results)

        socket
        |> assign(:cluster_users, cluster_users)
        |> assign(:loading, false)
    end
  end

  defp group_users_by_name(results) do
    results
    |> Enum.flat_map(fn {node, result} ->
      case result do
        {:ok, users} ->
          Enum.map(users, fn user ->
            {user["name"], %{node: node, user: user}}
          end)

        {:error, _} ->
          []
      end
    end)
    |> Enum.group_by(fn {name, _} -> name end, fn {_, data} -> data end)
    |> Enum.map(fn {name, nodes_data} ->
      first = List.first(nodes_data)
      group = first.user["group"]
      comment = first.user["comment"] || ""

      nodes_info =
        Enum.map(nodes_data, fn data ->
          %{
            node: data.node,
            id: data.user[".id"],
            last_logged_in: data.user["last-logged-in"] || "never",
            disabled: data.user["disabled"] == "true"
          }
        end)

      %{
        name: name,
        group: group,
        comment: comment,
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

  defp filter_users(users, "all"), do: users

  defp filter_users(users, group) do
    Enum.filter(users, &(&1.group == group))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <%!-- Header --%>
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold">RouterOS Users</h1>
            <p class="text-base-content/70">Manage system users across your RouterOS cluster</p>
          </div>
          <div class="flex gap-2">
            <button phx-click="refresh" class="btn btn-ghost btn-sm gap-2" disabled={@loading}>
              <.icon name="hero-arrow-path" class={["w-4 h-4", @loading && "animate-spin"]} /> Refresh
            </button>
            <%= if @current_scope.user do %>
              <.link patch={~p"/routeros-users/new"} class="btn btn-primary btn-sm gap-2">
                <.icon name="hero-plus" class="w-4 h-4" /> Add User
              </.link>
            <% end %>
          </div>
        </div>

        <%!-- Filter --%>
        <div class="flex gap-2">
          <div class="join">
            <button
              phx-click="filter"
              phx-value-group="all"
              class={["btn btn-sm join-item", @filter_group == "all" && "btn-active"]}
            >
              All
            </button>
            <button
              phx-click="filter"
              phx-value-group="full"
              class={["btn btn-sm join-item", @filter_group == "full" && "btn-active"]}
            >
              Full Access
            </button>
            <button
              phx-click="filter"
              phx-value-group="write"
              class={["btn btn-sm join-item", @filter_group == "write" && "btn-active"]}
            >
              Write
            </button>
            <button
              phx-click="filter"
              phx-value-group="read"
              class={["btn btn-sm join-item", @filter_group == "read" && "btn-active"]}
            >
              Read
            </button>
          </div>
        </div>

        <%= if @loading do %>
          <div class="flex items-center justify-center py-12">
            <span class="loading loading-spinner loading-lg"></span>
          </div>
        <% else %>
          <%= if @cluster_users == [] do %>
            <div class="text-center py-12 text-base-content/50">
              <.icon name="hero-user-group" class="size-12 mx-auto mb-3 opacity-50" />
              <p class="font-medium">No RouterOS users found</p>
              <p class="text-sm">Create your first RouterOS user to get started.</p>
            </div>
          <% else %>
            <div class="card bg-base-100 shadow-sm border border-base-300">
              <div class="card-body p-0">
                <div class="overflow-x-auto">
                  <table class="table table-sm">
                    <thead>
                      <tr>
                        <th>Username</th>
                        <th>Group</th>
                        <th>Comment</th>
                        <th>Nodes</th>
                        <th :if={@current_scope.user} class="w-20">Actions</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr
                        :for={user <- filter_users(@cluster_users, @filter_group)}
                        class="hover:bg-base-200/50"
                      >
                        <td>
                          <div class="flex items-center gap-2">
                            <.icon name="hero-user" class="w-4 h-4 text-secondary" />
                            <span class="font-medium">{user.name}</span>
                          </div>
                        </td>
                        <td>
                          <span class={[
                            "badge badge-sm",
                            user.group == "full" && "badge-success",
                            user.group == "write" && "badge-warning",
                            user.group == "read" && "badge-info"
                          ]}>
                            {user.group}
                          </span>
                        </td>
                        <td class="text-sm text-base-content/70">{user.comment}</td>
                        <td>
                          <div class="flex gap-1 flex-wrap">
                            <%= for node_info <- user.nodes do %>
                              <div
                                class="badge badge-outline badge-sm gap-1"
                                title={"Last login: #{node_info.last_logged_in}"}
                              >
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
                        <td :if={@current_scope.user}>
                          <div class="flex gap-1">
                            <.link
                              patch={~p"/routeros-users/#{user.name}/edit"}
                              class="btn btn-ghost btn-xs btn-square"
                              title="Edit user"
                            >
                              <.icon name="hero-pencil-square" class="w-4 h-4" />
                            </.link>
                            <button
                              type="button"
                              phx-click="delete"
                              phx-value-name={user.name}
                              data-confirm={"Delete user '#{user.name}' from ALL nodes in the cluster?"}
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

                  <div
                    :if={filter_users(@cluster_users, @filter_group) == []}
                    class="text-center py-8 text-base-content/50"
                  >
                    <p class="text-sm">No users match the current filter</p>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>

      <%!-- Add/Edit User Modal --%>
      <.modal
        :if={@live_action in [:new, :edit]}
        id="user-modal"
        show
        on_cancel={JS.patch(~p"/routeros-users")}
      >
        <h2 class="text-xl font-bold mb-4">
          {if @live_action == :edit, do: "Edit RouterOS User", else: "Add RouterOS User"}
        </h2>

        <.form for={@form} id="user-form" phx-change="validate" phx-submit="save" class="space-y-4">
          <.input
            field={@form[:name]}
            type="text"
            label="Username"
            required
            readonly={@live_action == :edit}
          />

          <.input
            field={@form[:password]}
            type="text"
            label={
              if @live_action == :edit,
                do: "New Password (leave empty to keep current)",
                else: "Password"
            }
            required={@live_action == :new}
            placeholder={
              if @live_action == :edit, do: "Leave empty to keep current password", else: ""
            }
          />

          <.input
            field={@form[:group]}
            type="select"
            label="Group"
            options={[
              {"Full Access", "full"},
              {"Write", "write"},
              {"Read Only", "read"}
            ]}
          />

          <.input field={@form[:comment]} type="text" label="Comment (optional)" />

          <div :if={@live_action == :new} class="form-control">
            <label class="label">
              <span class="label-text">Deploy To</span>
            </label>
            <select name="user[deploy_to]" class="select select-bordered">
              <option value="all">All Active Nodes</option>
              <option :for={node <- @available_nodes} value={node.name}>{node.name}</option>
            </select>
          </div>

          <div class="alert bg-warning/20 text-base-content border border-warning/30">
            <.icon name="hero-exclamation-triangle" class="w-5 h-5 text-warning" />
            <div class="text-sm">
              <p class="font-semibold">Security Note</p>
              <p>
                <%= if @live_action == :edit do %>
                  Changes will be applied to all nodes that have this user.
                <% else %>
                  This user will be created on the selected RouterOS device(s) and can access the device directly. Use strong passwords and appropriate group permissions.
                <% end %>
              </p>
            </div>
          </div>

          <div class="flex justify-end gap-2 pt-4">
            <.link patch={~p"/routeros-users"} class="btn btn-ghost">
              Cancel
            </.link>
            <button
              type="submit"
              class="btn btn-primary"
              phx-disable-with={if @live_action == :edit, do: "Updating...", else: "Creating..."}
            >
              {if @live_action == :edit, do: "Update User", else: "Create User"}
            </button>
          </div>
        </.form>
      </.modal>
    </Layouts.app>
    """
  end
end
