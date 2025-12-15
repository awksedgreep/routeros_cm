defmodule RouterosCm.ClusterFixtures do
  @moduledoc """
  Test fixtures for the Cluster context.
  """

  alias RouterosCm.Cluster

  @doc """
  Generate a unique node name.
  """
  def unique_node_name, do: "test-node-#{System.unique_integer([:positive])}"

  @doc """
  Generate a unique host.
  """
  def unique_host, do: "192.168.#{:rand.uniform(254)}.#{:rand.uniform(254)}"

  @doc """
  Create a node fixture with optional attributes.
  """
  def node_fixture(attrs \\ %{}) do
    {:ok, node} =
      attrs
      |> Enum.into(%{
        name: unique_node_name(),
        host: unique_host(),
        port: 8728,
        username: "admin",
        password: "test-password-123"
      })
      |> Cluster.create_node()

    node
  end

  @doc """
  Create multiple node fixtures.
  """
  def nodes_fixture(count, attrs \\ %{}) do
    Enum.map(1..count, fn _ -> node_fixture(attrs) end)
  end
end
