defmodule RouterosCm.Audit.LogPruner do
  @moduledoc """
  Periodic cleanup process for old audit logs.
  Deletes logs older than the configured retention period.
  """
  use GenServer
  require Logger

  import Ecto.Query
  alias RouterosCm.Repo
  alias RouterosCm.Audit.Log

  # Default: run weekly
  @default_interval :timer.hours(24 * 7)
  # Default: keep 3 months of logs
  @default_retention_days 90

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Triggers an immediate prune of old logs.
  Returns the number of deleted records.
  """
  def prune_now do
    GenServer.call(__MODULE__, :prune_now)
  end

  @doc """
  Returns the current configuration.
  """
  def get_config do
    GenServer.call(__MODULE__, :get_config)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, @default_interval)
    retention_days = Keyword.get(opts, :retention_days, @default_retention_days)

    # Schedule first prune after a short delay
    Process.send_after(self(), :prune, :timer.minutes(1))

    {:ok, %{interval: interval, retention_days: retention_days}}
  end

  @impl true
  def handle_call(:prune_now, _from, state) do
    count = perform_prune(state.retention_days)
    {:reply, count, state}
  end

  @impl true
  def handle_call(:get_config, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:prune, state) do
    perform_prune(state.retention_days)
    schedule_next_prune(state.interval)
    {:noreply, state}
  end

  defp perform_prune(retention_days) do
    cutoff = DateTime.utc_now() |> DateTime.add(-retention_days, :day)

    {count, _} =
      from(l in Log, where: l.inserted_at < ^cutoff)
      |> Repo.delete_all()

    if count > 0 do
      Logger.info("Audit log pruner: deleted #{count} logs older than #{retention_days} days")
    else
      Logger.debug("Audit log pruner: no logs to prune")
    end

    count
  end

  defp schedule_next_prune(interval) do
    Process.send_after(self(), :prune, interval)
  end
end
