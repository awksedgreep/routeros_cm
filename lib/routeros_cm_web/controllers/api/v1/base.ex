defmodule RouterosCmWeb.API.V1.Base do
  @moduledoc """
  Base module for API v1 controllers.

  Provides common helper functions for API responses, error handling,
  and scope checking.

  ## Usage

      defmodule RouterosCmWeb.API.V1.MyController do
        use RouterosCmWeb, :controller
        import RouterosCmWeb.API.V1.Base

        plug :require_scope, "my_resource:read" when action in [:index, :show]
        plug :require_scope, "my_resource:write" when action in [:create, :update, :delete]

        def index(conn, _params) do
          data = MyContext.list_items()
          json_response(conn, data)
        end
      end
  """

  import Plug.Conn
  import Phoenix.Controller

  alias RouterosCm.ApiAuth

  @doc """
  Returns a successful JSON response with data.
  """
  def json_response(conn, data, meta \\ %{}) do
    conn
    |> put_status(:ok)
    |> json(%{data: data, meta: meta})
  end

  @doc """
  Returns a successful JSON response for a created resource.
  """
  def json_created(conn, data, meta \\ %{}) do
    conn
    |> put_status(:created)
    |> json(%{data: data, meta: meta})
  end

  @doc """
  Returns a successful response with no content (204).
  """
  def json_no_content(conn) do
    conn
    |> put_status(:no_content)
    |> json(nil)
  end

  @doc """
  Returns a cluster operation result with successes and failures.
  """
  def json_cluster_result(conn, operation, resource, successes, failures) do
    status = if failures == [], do: :ok, else: :multi_status

    conn
    |> put_status(status)
    |> json(%{
      data: %{
        operation: operation,
        resource: resource,
        successes: format_node_results(successes),
        failures: format_node_errors(failures)
      }
    })
  end

  @doc """
  Returns a 400 Bad Request error.
  """
  def json_bad_request(conn, reason) do
    conn
    |> put_status(:bad_request)
    |> put_view(json: RouterosCmWeb.ErrorJSON)
    |> render("400.json", %{reason: reason})
  end

  @doc """
  Returns a 404 Not Found error.
  """
  def json_not_found(conn, resource \\ "Resource") do
    conn
    |> put_status(:not_found)
    |> put_view(json: RouterosCmWeb.ErrorJSON)
    |> render("404.json", %{resource: resource})
  end

  @doc """
  Returns a 422 Unprocessable Entity error with changeset errors.
  """
  def json_validation_error(conn, changeset) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: RouterosCmWeb.ErrorJSON)
    |> render("422.json", %{changeset: changeset})
  end

  @doc """
  Returns a 422 Unprocessable Entity error with custom errors.
  """
  def json_error(conn, errors) when is_map(errors) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: RouterosCmWeb.ErrorJSON)
    |> render("422.json", %{errors: errors})
  end

  def json_error(conn, message) when is_binary(message) do
    json_error(conn, %{error: message})
  end

  @doc """
  Returns a 500 Internal Server Error.
  """
  def json_internal_error(conn) do
    conn
    |> put_status(:internal_server_error)
    |> put_view(json: RouterosCmWeb.ErrorJSON)
    |> render("500.json")
  end

  @doc """
  Plug function to check if the current token has the required scope.

  Use in controllers like:

      plug :require_scope, "dns:write" when action in [:create, :update, :delete]

  """
  def require_scope(conn, required_scope) do
    api_token = conn.assigns[:api_token]

    if api_token && ApiAuth.has_scope?(api_token, required_scope) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> put_view(json: RouterosCmWeb.ErrorJSON)
      |> render("403.json", %{scope: required_scope})
      |> halt()
    end
  end

  @doc """
  Gets the current scope from the connection.
  """
  def current_scope(conn) do
    conn.assigns[:current_scope]
  end

  @doc """
  Gets the API token from the connection.
  """
  def api_token(conn) do
    conn.assigns[:api_token]
  end

  # Private helpers

  defp format_node_results(results) do
    Enum.map(results, fn
      {node, {:ok, data}} when is_map(data) ->
        %{node: node.name, node_id: node.id, id: data[".id"]}

      {node, {:ok, _}} ->
        %{node: node.name, node_id: node.id}

      {:ok, node, status} ->
        %{node: node.name, node_id: node.id, status: status}

      {node, _} ->
        %{node: node.name, node_id: node.id}
    end)
  end

  defp format_node_errors(failures) do
    Enum.map(failures, fn
      {node, {:error, reason}} when is_struct(node) ->
        %{node: node.name, error: format_error(reason)}

      {:error, node, reason} when is_struct(node) ->
        %{node: node.name, error: format_error(reason)}

      {node, error} when is_struct(node) ->
        %{node: node.name, error: format_error(error)}

      {:timeout, :timeout} ->
        %{node: "unknown", error: "timeout"}

      other ->
        %{error: format_error(other)}
    end)
  end

  defp format_error(%{detail: detail}), do: detail
  defp format_error(reason) when is_atom(reason), do: to_string(reason)
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
