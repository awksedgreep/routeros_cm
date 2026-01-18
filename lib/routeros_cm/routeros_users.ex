defmodule RouterosCm.RouterOSUsers do
  @moduledoc """
  Context for managing RouterOS system users across the cluster.

  This module provides functions to manage RouterOS users (not PPP users).
  All operations are performed directly against the RouterOS API without
  local database storage.
  """

  alias RouterosCm.{Audit, Cluster, MikroTik}
  require Logger

  @timeout 15_000

  @doc """
  Lists all RouterOS users across specified nodes.

  ## Options

    * `:nodes` - List of nodes to query. Defaults to all active nodes.
    * `:current_scope` - Current user scope for audit logging.

  Returns `{:ok, users_by_node}` where users_by_node is a list of
  `{node, {:ok, users} | {:error, reason}}` tuples.
  """
  def list_routeros_users(opts \\ []) do
    current_scope = Keyword.get(opts, :current_scope)
    nodes = Keyword.get(opts, :nodes) || Cluster.list_active_nodes()

    results =
      nodes
      |> Task.async_stream(
        fn node ->
          case MikroTik.Client.list_routeros_users(node) do
            {:ok, users} ->
              {node, {:ok, users}}

            {:error, reason} = error ->
              Logger.error("Failed to list RouterOS users on #{node.name}: #{inspect(reason)}")

              if current_scope do
                Audit.log_failure(
                  "list_routeros_users",
                  "routeros_users",
                  node.name,
                  user_id: current_scope.user.id,
                  details: %{error: inspect(reason)}
                )
              end

              {node, error}
          end
        end,
        timeout: @timeout,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, :timeout} -> {:error, :timeout}
      end)

    {:ok, results}
  end

  @doc """
  Creates a RouterOS user on specified nodes.

  ## Parameters

    * `user_params` - Map with user parameters:
      * `:name` - Username (required)
      * `:password` - Password (required)
      * `:group` - User group (default: "full")
      * `:comment` - Optional comment
    * `node_names` - List of node names to create user on. Pass "all" for cluster-wide.
    * `current_scope` - Current user scope for audit logging.

  Returns `{:ok, successes, failures}` where:
    * `successes` - List of nodes where creation succeeded
    * `failures` - List of `{node, error}` tuples
  """
  def create_routeros_user(user_params, node_names, current_scope) do
    nodes = get_target_nodes(node_names)
    username = Map.get(user_params, "name") || Map.get(user_params, :name)

    results =
      nodes
      |> Task.async_stream(
        fn node ->
          case MikroTik.Client.create_routeros_user(node, user_params) do
            {:ok, _} ->
              Audit.log_routeros_user_action("create", username, %{
                user_id: current_scope.user.id,
                node_name: node.name,
                details: %{group: user_params["group"] || user_params[:group] || "full"}
              })

              {:ok, node}

            {:error, reason} = error ->
              Logger.error(
                "Failed to create RouterOS user '#{username}' on #{node.name}: #{inspect(reason)}"
              )

              Audit.log_failure(
                "create",
                "routeros_user",
                username,
                user_id: current_scope.user.id,
                node_name: node.name,
                details: %{error: inspect(reason)}
              )

              {node, error}
          end
        end,
        timeout: @timeout,
        on_timeout: :kill_task
      )
      |> Enum.reduce({[], []}, fn
        {:ok, {:ok, node}}, {successes, failures} ->
          {[node | successes], failures}

        {:ok, {node, error}}, {successes, failures} ->
          {successes, [{node, error} | failures]}

        {:exit, :timeout}, {successes, failures} ->
          {successes, [{:timeout, :timeout} | failures]}
      end)

    {successes, failures} = results
    {:ok, successes, failures}
  end

  @doc """
  Updates a RouterOS user on specified nodes.

  ## Parameters

    * `user_id` - The RouterOS user ID (typically "*XX" format)
    * `user_params` - Map with fields to update (password, group, comment, etc.)
    * `node_names` - List of node names to update user on
    * `current_scope` - Current user scope for audit logging

  Returns `{:ok, successes, failures}`.
  """
  def update_routeros_user(user_id, user_params, node_names, current_scope) do
    nodes = get_target_nodes(node_names)
    username = Map.get(user_params, "name") || Map.get(user_params, :name) || user_id

    results =
      nodes
      |> Task.async_stream(
        fn node ->
          case MikroTik.Client.update_routeros_user(node, user_id, user_params) do
            {:ok, _} ->
              Audit.log_routeros_user_action("update", username, %{
                user_id: current_scope.user.id,
                node_name: node.name,
                details: %{user_id: user_id, changes: user_params}
              })

              {:ok, node}

            {:error, reason} = error ->
              Logger.error(
                "Failed to update RouterOS user '#{username}' on #{node.name}: #{inspect(reason)}"
              )

              Audit.log_failure(
                "update",
                "routeros_user",
                username,
                user_id: current_scope.user.id,
                node_name: node.name,
                details: %{error: inspect(reason)}
              )

              {node, error}
          end
        end,
        timeout: @timeout,
        on_timeout: :kill_task
      )
      |> Enum.reduce({[], []}, fn
        {:ok, {:ok, node}}, {successes, failures} ->
          {[node | successes], failures}

        {:ok, {node, error}}, {successes, failures} ->
          {successes, [{node, error} | failures]}

        {:exit, :timeout}, {successes, failures} ->
          {successes, [{:timeout, :timeout} | failures]}
      end)

    {successes, failures} = results
    {:ok, successes, failures}
  end

  @doc """
  Deletes a RouterOS user from specified nodes.

  ## Parameters

    * `username` - Username to display in audit logs
    * `user_id` - The RouterOS user ID
    * `node_names` - List of node names to delete user from
    * `current_scope` - Current user scope for audit logging

  Returns `{:ok, successes, failures}`.
  """
  def delete_routeros_user(username, user_id, node_names, current_scope) do
    nodes = get_target_nodes(node_names)

    results =
      nodes
      |> Task.async_stream(
        fn node ->
          case MikroTik.Client.delete_routeros_user(node, user_id) do
            {:ok, _} ->
              Audit.log_routeros_user_action("delete", username, %{
                user_id: current_scope.user.id,
                node_name: node.name,
                details: %{user_id: user_id}
              })

              {:ok, node}

            {:error, reason} = error ->
              Logger.error(
                "Failed to delete RouterOS user '#{username}' on #{node.name}: #{inspect(reason)}"
              )

              Audit.log_failure(
                "delete",
                "routeros_user",
                username,
                user_id: current_scope.user.id,
                node_name: node.name,
                details: %{error: inspect(reason)}
              )

              {node, error}
          end
        end,
        timeout: @timeout,
        on_timeout: :kill_task
      )
      |> Enum.reduce({[], []}, fn
        {:ok, {:ok, node}}, {successes, failures} ->
          {[node | successes], failures}

        {:ok, {node, error}}, {successes, failures} ->
          {successes, [{node, error} | failures]}

        {:exit, :timeout}, {successes, failures} ->
          {successes, [{:timeout, :timeout} | failures]}
      end)

    {successes, failures} = results
    {:ok, successes, failures}
  end

  @doc """
  Deletes a RouterOS user by name from all active nodes in the cluster.
  Finds the user ID on each node and deletes it.

  ## Parameters

    * `username` - Username to delete
    * `current_scope` - Current user scope for audit logging

  Returns `{:ok, successes, failures}`.
  """
  def delete_routeros_user_by_name(username, current_scope) do
    nodes = Cluster.list_active_nodes()

    results =
      nodes
      |> Task.async_stream(
        fn node ->
          # First find the user by name on this node
          case MikroTik.Client.list_routeros_users(node) do
            {:ok, users} ->
              case Enum.find(users, &(&1["name"] == username)) do
                nil ->
                  # User doesn't exist on this node, that's OK
                  {:ok, node, :not_found}

                user ->
                  case MikroTik.Client.delete_routeros_user(node, user[".id"]) do
                    {:ok, _} ->
                      Audit.log_routeros_user_action("delete", username, %{
                        user_id: current_scope.user.id,
                        node_name: node.name,
                        details: %{cluster_wide: true}
                      })

                      {:ok, node, :deleted}

                    {:error, reason} ->
                      Logger.error(
                        "Failed to delete RouterOS user '#{username}' on #{node.name}: #{inspect(reason)}"
                      )

                      {:error, node, reason}
                  end
              end

            {:error, reason} ->
              Logger.error("Failed to list RouterOS users on #{node.name}: #{inspect(reason)}")
              {:error, node, reason}
          end
        end,
        timeout: @timeout,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, :timeout} -> {:error, nil, :timeout}
      end)
      |> Enum.reject(fn {_, node, _} -> is_nil(node) end)

    {successes, failures} = Enum.split_with(results, &match?({:ok, _, _}, &1))

    {:ok, successes, failures}
  end

  @doc """
  Updates a RouterOS user by name across all active nodes in the cluster.
  Finds the user ID on each node and updates it.

  ## Parameters

    * `username` - Username to update
    * `attrs` - Attributes to update (group, comment, password if provided)
    * `current_scope` - Current user scope for audit logging

  Returns `{:ok, successes, failures}`.
  """
  def update_routeros_user_by_name(username, attrs, current_scope) do
    nodes = Cluster.list_active_nodes()

    # Build update attributes, only include password if it's not empty
    update_attrs =
      %{
        "group" => attrs["group"],
        "comment" => attrs["comment"] || ""
      }
      |> maybe_add_password(attrs["password"])

    results =
      nodes
      |> Task.async_stream(
        fn node ->
          # First find the user by name on this node
          case MikroTik.Client.list_routeros_users(node) do
            {:ok, users} ->
              case Enum.find(users, &(&1["name"] == username)) do
                nil ->
                  # User doesn't exist on this node - skip (or could create)
                  {:ok, node, :not_found}

                user ->
                  case MikroTik.Client.update_routeros_user(node, user[".id"], update_attrs) do
                    {:ok, _} ->
                      Audit.log_routeros_user_action("update", username, %{
                        user_id: current_scope.user.id,
                        node_name: node.name,
                        details: %{
                          cluster_wide: true,
                          attrs: Map.delete(update_attrs, "password")
                        }
                      })

                      {:ok, node, :updated}

                    {:error, reason} ->
                      Logger.error(
                        "Failed to update RouterOS user '#{username}' on #{node.name}: #{inspect(reason)}"
                      )

                      {:error, node, reason}
                  end
              end

            {:error, reason} ->
              Logger.error("Failed to list RouterOS users on #{node.name}: #{inspect(reason)}")
              {:error, node, reason}
          end
        end,
        timeout: @timeout,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, :timeout} -> {:error, nil, :timeout}
      end)
      |> Enum.reject(fn {_, node, _} -> is_nil(node) end)

    {successes, failures} = Enum.split_with(results, &match?({:ok, _, _}, &1))

    {:ok, successes, failures}
  end

  defp maybe_add_password(attrs, nil), do: attrs
  defp maybe_add_password(attrs, ""), do: attrs
  defp maybe_add_password(attrs, password), do: Map.put(attrs, "password", password)

  @doc """
  Lists all user groups on specified nodes.

  Returns `{:ok, groups_by_node}`.
  """
  def list_user_groups(opts \\ []) do
    nodes = Keyword.get(opts, :nodes) || Cluster.list_active_nodes()

    results =
      nodes
      |> Task.async_stream(
        fn node ->
          case MikroTik.Client.list_user_groups(node) do
            {:ok, groups} -> {node, {:ok, groups}}
            {:error, _reason} = error -> {node, error}
          end
        end,
        timeout: @timeout,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, :timeout} -> {:error, :timeout}
      end)

    {:ok, results}
  end

  @doc """
  Lists active user sessions on specified nodes.

  Returns `{:ok, sessions_by_node}`.
  """
  def list_active_users(opts \\ []) do
    nodes = Keyword.get(opts, :nodes) || Cluster.list_active_nodes()

    results =
      nodes
      |> Task.async_stream(
        fn node ->
          case MikroTik.Client.list_active_users(node) do
            {:ok, sessions} -> {node, {:ok, sessions}}
            {:error, _reason} = error -> {node, error}
          end
        end,
        timeout: @timeout,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, :timeout} -> {:error, :timeout}
      end)

    {:ok, results}
  end

  # Private helpers

  defp get_target_nodes("all"), do: Cluster.list_active_nodes()

  defp get_target_nodes(node_names) when is_list(node_names) do
    node_names
    |> Enum.map(&Cluster.get_node_by_name!/1)
  end
end
