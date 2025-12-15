defmodule RouterosCm.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      RouterosCmWeb.Telemetry,
      RouterosCm.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:routeros_cm, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:routeros_cm, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: RouterosCm.PubSub},
      # Periodic health check for cluster nodes
      RouterosCm.Cluster.HealthCheck,
      # Periodic cleanup of old audit logs
      RouterosCm.Audit.LogPruner,
      # Start to serve requests, typically the last entry
      RouterosCmWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: RouterosCm.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RouterosCmWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
