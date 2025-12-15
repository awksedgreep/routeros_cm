defmodule RouterosCmWeb.NodeLive.FormComponent do
  use RouterosCmWeb, :live_component
  alias RouterosCm.Cluster

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Configure your RouterOS node connection details</:subtitle>
      </.header>

      <.form
        for={@form}
        id="node-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <div class="space-y-4 mt-4">
          <.input field={@form[:name]} type="text" label="Node Name" required />
          <.input field={@form[:host]} type="text" label="Host" placeholder="192.168.1.1" required />
          <.input
            field={@form[:port]}
            type="number"
            label="Port"
            value={@form[:port].value || 8728}
            required
          />
          <.input field={@form[:username]} type="text" label="Username" required />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            required={@action == :new}
            placeholder={if @action == :edit, do: "Leave blank to keep current password", else: nil}
          />
        </div>

        <div class="mt-6 flex items-center justify-end gap-2">
          <.button type="button" phx-click={JS.exec("data-cancel", to: "#node-modal")} class="btn">
            Cancel
          </.button>
          <.button type="submit" phx-disable-with="Saving..." class="btn btn-primary">
            Save Node
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_form()}
  end

  @impl true
  def handle_event("validate", %{"node" => node_params}, socket) do
    changeset =
      socket.assigns.node
      |> Cluster.change_node(node_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"node" => node_params}, socket) do
    save_node(socket, socket.assigns.action, node_params)
  end

  defp save_node(socket, :new, node_params) do
    case Cluster.create_node(socket.assigns.current_scope, node_params) do
      {:ok, node} ->
        notify_parent({:node_saved, node})

        {:noreply,
         socket
         |> put_flash(:info, "Node created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_node(socket, :edit, node_params) do
    case Cluster.update_node(socket.assigns.current_scope, socket.assigns.node, node_params) do
      {:ok, node} ->
        notify_parent({:node_saved, node})

        {:noreply,
         socket
         |> put_flash(:info, "Node updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp assign_form(socket) do
    changeset = Cluster.change_node(socket.assigns.node)
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), msg)
end
