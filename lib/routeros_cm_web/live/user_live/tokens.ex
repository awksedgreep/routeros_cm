defmodule RouterosCmWeb.UserLive.Tokens do
  use RouterosCmWeb, :live_view

  on_mount {RouterosCmWeb.UserAuth, :require_sudo_mode}

  alias RouterosCm.ApiAuth
  alias RouterosCm.Accounts.ApiToken

  @scope_groups [
    {"Nodes", [{"nodes:read", "View nodes"}, {"nodes:write", "Manage nodes"}]},
    {"DNS", [{"dns:read", "View DNS records"}, {"dns:write", "Manage DNS records"}]},
    {"Tunnels", [{"tunnels:read", "View GRE tunnels"}, {"tunnels:write", "Manage GRE tunnels"}]},
    {"WireGuard",
     [{"wireguard:read", "View WireGuard"}, {"wireguard:write", "Manage WireGuard"}]},
    {"RouterOS Users", [{"users:read", "View users"}, {"users:write", "Manage users"}]},
    {"Audit", [{"audit:read", "View audit logs"}]}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        API Tokens
        <:subtitle>
          Create and manage API tokens for programmatic access to the API.
        </:subtitle>
        <:actions>
          <.link patch={~p"/users/settings/tokens/new"} class="btn btn-primary btn-sm">
            <.icon name="hero-plus" class="size-4" /> New Token
          </.link>
        </:actions>
      </.header>

      <div class="mt-6">
        <div class="card bg-base-100 shadow-sm border border-base-300">
          <div class="card-body p-0">
            <div class="overflow-x-auto">
              <table class="table">
                <thead>
                  <tr>
                    <th>Name</th>
                    <th>Scopes</th>
                    <th>Last Used</th>
                    <th>Created</th>
                    <th>Expires</th>
                    <th class="w-24">Actions</th>
                  </tr>
                </thead>
                <tbody id="tokens" phx-update="stream">
                  <tr
                    :for={{dom_id, token} <- @streams.tokens}
                    id={dom_id}
                    class="hover:bg-base-200/50 transition-colors"
                  >
                    <td>
                      <div class="font-medium">{token.name}</div>
                      <div :if={token.description} class="text-xs text-base-content/60">
                        {token.description}
                      </div>
                    </td>
                    <td>
                      <div class="flex flex-wrap gap-1">
                        <span
                          :for={scope <- token.scopes}
                          class="badge badge-ghost badge-sm font-mono"
                        >
                          {scope}
                        </span>
                        <span :if={token.scopes == []} class="text-base-content/40 text-sm">
                          No scopes
                        </span>
                      </div>
                    </td>
                    <td class="text-sm text-base-content/70">
                      {format_datetime(token.last_used_at) || "Never"}
                    </td>
                    <td class="text-sm text-base-content/70">
                      {format_datetime(token.inserted_at)}
                    </td>
                    <td class="text-sm">
                      <span :if={token.expires_at} class={expiry_class(token.expires_at)}>
                        {format_datetime(token.expires_at)}
                      </span>
                      <span :if={!token.expires_at} class="text-base-content/40">Never</span>
                    </td>
                    <td>
                      <button
                        type="button"
                        phx-click="revoke"
                        phx-value-id={token.id}
                        data-confirm={"Are you sure you want to revoke the token \"#{token.name}\"? This cannot be undone."}
                        class="btn btn-ghost btn-xs btn-square text-error"
                        title="Revoke Token"
                      >
                        <.icon name="hero-trash" class="size-4" />
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>

              <div
                :if={@token_count == 0}
                class="text-center py-12 text-base-content/50"
              >
                <.icon name="hero-key" class="size-12 mx-auto mb-3 opacity-50" />
                <p class="font-medium">No API tokens</p>
                <p class="text-sm">Create a token to access the API programmatically.</p>
              </div>
            </div>
          </div>
        </div>
      </div>

      <.modal
        :if={@live_action == :new}
        id="new-token-modal"
        show
        on_cancel={JS.patch(~p"/users/settings/tokens")}
      >
        <:header>Create API Token</:header>
        <.form for={@form} id="token-form" phx-change="validate" phx-submit="save">
          <div class="space-y-4">
            <.input field={@form[:name]} type="text" label="Token Name" required />
            <.input field={@form[:description]} type="textarea" label="Description (optional)" />

            <div>
              <label class="label">
                <span class="label-text font-medium">Scopes</span>
              </label>
              <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-2">
                <div :for={{group_name, scopes} <- @scope_groups} class="space-y-2">
                  <div class="font-medium text-sm text-base-content/70">{group_name}</div>
                  <div :for={{scope, description} <- scopes} class="flex items-start gap-2">
                    <input
                      type="checkbox"
                      name="api_token[scopes][]"
                      value={scope}
                      checked={scope in (@form[:scopes].value || [])}
                      class="checkbox checkbox-sm mt-0.5"
                      id={"scope-#{scope}"}
                    />
                    <label for={"scope-#{scope}"} class="text-sm cursor-pointer">
                      <span class="font-mono">{scope}</span>
                      <span class="text-base-content/60 block text-xs">{description}</span>
                    </label>
                  </div>
                </div>
              </div>
            </div>

            <.input field={@form[:expires_at]} type="date" label="Expiration Date (optional)" />
          </div>

          <div class="mt-6 flex items-center justify-end gap-2">
            <.button
              type="button"
              phx-click={JS.exec("data-cancel", to: "#new-token-modal")}
              class="btn"
            >
              Cancel
            </.button>
            <.button type="submit" phx-disable-with="Creating..." class="btn btn-primary">
              Create Token
            </.button>
          </div>
        </.form>
      </.modal>

      <.modal
        :if={@created_token}
        id="token-created-modal"
        show
        on_cancel={JS.push("clear_created_token")}
      >
        <:header>Token Created Successfully</:header>
        <div class="space-y-4">
          <div class="alert alert-warning">
            <.icon name="hero-exclamation-triangle" class="size-5" />
            <span>
              Copy this token now. You won't be able to see it again!
            </span>
          </div>

          <div>
            <label class="label">
              <span class="label-text font-medium">Your API Token</span>
            </label>
            <div class="join w-full">
              <input
                type="text"
                readonly
                value={@created_token}
                class="input input-bordered join-item flex-1 font-mono text-sm"
                id="created-token-input"
              />
              <button
                type="button"
                class="btn join-item"
                onclick="navigator.clipboard.writeText(document.getElementById('created-token-input').value).then(() => this.classList.add('btn-success'))"
              >
                <.icon name="hero-clipboard-document" class="size-4" /> Copy
              </button>
            </div>
          </div>

          <div class="text-sm text-base-content/70">
            <p class="font-medium mb-2">Usage example:</p>
            <pre class="bg-base-200 p-3 rounded-lg overflow-x-auto"><code>{curl_example(@created_token)}</code></pre>
          </div>
        </div>

        <div class="mt-6 flex justify-end">
          <.button phx-click="clear_created_token" class="btn btn-primary">
            Done
          </.button>
        </div>
      </.modal>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    tokens = ApiAuth.list_tokens(user.id)

    {:ok,
     socket
     |> assign(:page_title, "API Tokens")
     |> assign(:scope_groups, @scope_groups)
     |> assign(:created_token, nil)
     |> assign(:token_count, length(tokens))
     |> stream(:tokens, tokens)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "API Tokens")
    |> assign(:form, nil)
  end

  defp apply_action(socket, :new, _params) do
    changeset = ApiAuth.change_token(%ApiToken{}, %{scopes: []})

    socket
    |> assign(:page_title, "New API Token")
    |> assign(:form, to_form(changeset))
  end

  @impl true
  def handle_event("validate", %{"api_token" => token_params}, socket) do
    token_params = normalize_params(token_params)

    changeset =
      %ApiToken{}
      |> ApiAuth.change_token(token_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"api_token" => token_params}, socket) do
    user = socket.assigns.current_scope.user
    token_params = normalize_params(token_params)

    case ApiAuth.create_token_for_user(user, token_params) do
      {:ok, token} ->
        {:noreply,
         socket
         |> assign(:created_token, token.token)
         |> assign(:token_count, socket.assigns.token_count + 1)
         |> stream_insert(:tokens, token, at: 0)
         |> push_patch(to: ~p"/users/settings/tokens")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    token = ApiAuth.get_token!(id)

    if token.user_id == user.id do
      {:ok, _} = ApiAuth.revoke_token(token)

      {:noreply,
       socket
       |> assign(:token_count, socket.assigns.token_count - 1)
       |> stream_delete(:tokens, token)
       |> put_flash(:info, "Token \"#{token.name}\" has been revoked.")}
    else
      {:noreply, put_flash(socket, :error, "You can only revoke your own tokens.")}
    end
  end

  def handle_event("clear_created_token", _params, socket) do
    {:noreply, assign(socket, :created_token, nil)}
  end

  # Helpers

  defp normalize_params(params) do
    params
    |> Map.put_new("scopes", [])
    |> Map.update("expires_at", nil, fn
      "" -> nil
      date when is_binary(date) -> parse_date(date)
      other -> other
    end)
  end

  defp parse_date(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        DateTime.new!(date, ~T[23:59:59], "Etc/UTC")

      _ ->
        nil
    end
  end

  defp format_datetime(nil), do: nil

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %H:%M")
  end

  defp expiry_class(expires_at) do
    now = DateTime.utc_now()

    cond do
      DateTime.compare(expires_at, now) == :lt ->
        "text-error"

      DateTime.compare(expires_at, DateTime.add(now, 7, :day)) == :lt ->
        "text-warning"

      true ->
        "text-base-content/70"
    end
  end

  defp curl_example(token) do
    url = RouterosCmWeb.Endpoint.url()
    "curl -H \"Authorization: Bearer #{token}\" #{url}/api/v1/nodes"
  end
end
