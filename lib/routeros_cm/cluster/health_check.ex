defmodule RouterosCm.Cluster.HealthCheck do
  @moduledoc """
  Periodic health check process for cluster nodes.
  Pings all nodes at a configurable interval and updates their status.
  """
  use GenServer
  require Logger

  alias RouterosCm.Cluster

  @default_interval :timer.seconds(60)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Triggers an immediate health check of all nodes.
  """
  def check_now do
    GenServer.cast(__MODULE__, :check_now)
  end

  @doc """
  Returns the current health check interval in milliseconds.
  """
  def get_interval do
    GenServer.call(__MODULE__, :get_interval)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, @default_interval)

    # Schedule first check after a short delay to let app fully start
    Process.send_after(self(), :check, :timer.seconds(5))

    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_cast(:check_now, state) do
    perform_health_checks()
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_interval, _from, state) do
    {:reply, state.interval, state}
  end

  @impl true
  def handle_info(:check, state) do
    perform_health_checks()
    schedule_next_check(state.interval)
    {:noreply, state}
  end

  defp perform_health_checks do
    nodes = Cluster.list_nodes()
    Logger.debug("Health check: checking #{length(nodes)} nodes")

    Enum.each(nodes, fn node ->
      Task.start(fn -> check_node(node) end)
    end)
  end

  defp check_node(node) do
    case Cluster.test_connection(node) do
      {:ok, _} ->
        Logger.debug("Health check: #{node.name} is online")

      {:error, reason} ->
        Logger.debug("Health check: #{node.name} is offline - #{inspect(reason)}")
        Cluster.set_node_offline(node)
    end
  end

  defp schedule_next_check(interval) do
    Process.send_after(self(), :check, interval)
  end
end
