defmodule RouterosCmWeb.Router do
  use RouterosCmWeb, :router

  import RouterosCmWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {RouterosCmWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug RouterosCmWeb.Plugs.APIAuth
  end

  pipeline :api_public do
    plug :accepts, ["json", "html"]
  end

  scope "/", RouterosCmWeb do
    pipe_through :browser
  end

  # API documentation (public, no auth required)
  scope "/api/v1", RouterosCmWeb.API.V1, as: :api_v1_docs do
    pipe_through :api_public

    get "/openapi", OpenApiController, :spec
    get "/docs", OpenApiController, :swaggerui
  end

  # API v1 routes
  scope "/api/v1", RouterosCmWeb.API.V1, as: :api_v1 do
    pipe_through :api

    # Cluster & Node management
    resources "/nodes", NodeController, except: [:new, :edit]
    post "/nodes/:id/test", NodeController, :test
    get "/cluster/health", ClusterController, :health
    get "/cluster/stats", ClusterController, :stats

    # DNS management
    get "/dns/records", DNSController, :index
    get "/dns/records/:name", DNSController, :show
    post "/dns/records", DNSController, :create
    patch "/dns/records/:name", DNSController, :update
    put "/dns/records/:name", DNSController, :update
    delete "/dns/records/:name", DNSController, :delete
    get "/dns/settings", DNSController, :settings
    patch "/dns/settings", DNSController, :update_settings
    post "/dns/cache/flush", DNSController, :flush_cache

    # GRE Tunnel management
    get "/gre", GREController, :index
    get "/gre/:name", GREController, :show
    post "/gre", GREController, :create
    delete "/gre/:name", GREController, :delete
    post "/gre/:name/ip", GREController, :assign_ip
    delete "/gre/:name/ip/:address", GREController, :remove_ip

    # WireGuard management
    get "/wireguard", WireGuardController, :index
    get "/wireguard/:name", WireGuardController, :show
    post "/wireguard", WireGuardController, :create
    delete "/wireguard/:name", WireGuardController, :delete
    post "/wireguard/:name/ip", WireGuardController, :assign_ip
    delete "/wireguard/:name/ip/:address", WireGuardController, :remove_ip
    get "/wireguard/:name/peers", WireGuardController, :list_peers
    post "/wireguard/:name/peers", WireGuardController, :create_peer
    delete "/wireguard/:name/peers/:public_key", WireGuardController, :delete_peer
    post "/wireguard/generate-keypair", WireGuardController, :generate_keypair

    # RouterOS Users management
    get "/routeros-users", RouterOSUserController, :index
    get "/routeros-users/groups", RouterOSUserController, :groups
    get "/routeros-users/active", RouterOSUserController, :active_sessions
    get "/routeros-users/:name", RouterOSUserController, :show
    post "/routeros-users", RouterOSUserController, :create
    patch "/routeros-users/:name", RouterOSUserController, :update
    put "/routeros-users/:name", RouterOSUserController, :update
    delete "/routeros-users/:name", RouterOSUserController, :delete

    # Audit logs
    get "/audit", AuditController, :index
    get "/audit/stats", AuditController, :stats
    get "/audit/:id", AuditController, :show
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:routeros_cm, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: RouterosCmWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", RouterosCmWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{RouterosCmWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
      live "/users/settings/tokens", UserLive.Tokens, :index
      live "/users/settings/tokens/new", UserLive.Tokens, :new

      # Dashboard
      live "/", DashboardLive, :index

      # Cluster management routes
      live "/nodes", NodeLive.Index, :index
      live "/nodes/new", NodeLive.Index, :new
      live "/nodes/:id/edit", NodeLive.Index, :edit
      live "/nodes/:id/show", NodeLive.Show, :show

      # DNS management
      live "/dns", DNSLive.Index, :index
      live "/dns/new", DNSLive.Index, :new
      live "/dns/:name/edit", DNSLive.Index, :edit

      # RouterOS Users management
      live "/routeros-users", RouterOSUsersLive.Index, :index
      live "/routeros-users/new", RouterOSUsersLive.Index, :new
      live "/routeros-users/:name/edit", RouterOSUsersLive.Index, :edit

      # WireGuard management
      live "/wireguard", WireGuardLive.Index, :index
      live "/wireguard/new", WireGuardLive.Index, :new
      live "/wireguard/:interface_name/assign-ip", WireGuardLive.Index, :assign_ip
      live "/wireguard/:interface_name/peers", WireGuardLive.Peers, :index
      live "/wireguard/:interface_name/peers/new", WireGuardLive.Peers, :new

      # GRE Tunnels management
      live "/gre", GRELive.Index, :index
      live "/gre/new", GRELive.Index, :new
      live "/gre/:interface_name/assign-ip", GRELive.Index, :assign_ip

      # Audit logs
      live "/audit", AuditLive.Index, :index
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", RouterosCmWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{RouterosCmWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
