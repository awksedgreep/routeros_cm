defmodule RouterosCmWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use RouterosCmWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true
  slot :header, doc: "optional header content"

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8 bg-base-200">
      <div class="flex-1">
        <.link navigate="/" class="flex items-center gap-2">
          <span class="text-xl font-bold">RouterOS CM</span>
        </.link>
      </div>
      <div class="flex-none">
        <ul class="flex px-1 space-x-2 items-center">
          <%= if @current_scope && @current_scope.user do %>
            <li>
              <.link navigate={~p"/"} class="btn btn-ghost btn-sm">
                <.icon name="hero-home" class="w-4 h-4" /> Dashboard
              </.link>
            </li>
            <li>
              <.link navigate={~p"/nodes"} class="btn btn-ghost btn-sm">
                <.icon name="hero-server" class="w-4 h-4" /> Nodes
              </.link>
            </li>
            <li>
              <.link navigate={~p"/dns"} class="btn btn-ghost btn-sm">
                <.icon name="hero-globe-alt" class="w-4 h-4" /> DNS
              </.link>
            </li>
            <li class="dropdown dropdown-hover">
              <div tabindex="0" role="button" class="btn btn-ghost btn-sm">
                <.icon name="hero-arrows-right-left" class="w-4 h-4" /> Tunnels
              </div>
              <ul
                tabindex="0"
                class="dropdown-content menu bg-base-100 rounded-box z-[1] w-52 p-2 shadow"
              >
                <li>
                  <.link navigate={~p"/wireguard"}>
                    <.icon name="hero-shield-check" class="w-4 h-4" /> WireGuard
                  </.link>
                </li>
                <li>
                  <.link navigate={~p"/gre"}>
                    <.icon name="hero-arrows-right-left" class="w-4 h-4" /> GRE
                  </.link>
                </li>
              </ul>
            </li>
            <li>
              <.link navigate={~p"/routeros-users"} class="btn btn-ghost btn-sm">
                <.icon name="hero-user-group" class="w-4 h-4" /> Users
              </.link>
            </li>
            <li>
              <.link navigate={~p"/audit"} class="btn btn-ghost btn-sm">
                <.icon name="hero-clipboard-document-list" class="w-4 h-4" /> Audit
              </.link>
            </li>
            <li>
              <.link navigate={~p"/users/settings"} class="btn btn-ghost btn-sm">
                <.icon name="hero-cog-6-tooth" class="w-4 h-4" /> Settings
              </.link>
            </li>
            <li>
              <.link href={~p"/users/log-out"} method="delete" class="btn btn-ghost btn-sm">
                <.icon name="hero-arrow-right-on-rectangle" class="w-4 h-4" /> Log out
              </.link>
            </li>
          <% else %>
            <li>
              <.link navigate={~p"/users/log-in"} class="btn btn-primary btn-sm">
                Log in
              </.link>
            </li>
          <% end %>
          <li>
            <.theme_toggle />
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-6 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-7xl">
        <div :if={@header != []} class="mb-6">
          {render_slot(@header)}
        </div>
        <div class="space-y-4">
          {render_slot(@inner_block)}
        </div>
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
