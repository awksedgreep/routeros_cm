defmodule RouterosCmWeb.Plugs.APIAuth do
  @moduledoc """
  Plug for authenticating API requests using bearer tokens.

  ## Usage

  Add to your API pipeline in router.ex:

      pipeline :api do
        plug :accepts, ["json"]
        plug RouterosCmWeb.Plugs.APIAuth
      end

  ## Authentication

  Requests must include an Authorization header with a bearer token:

      Authorization: Bearer <token>

  ## Scope Checking

  Use `require_scope/2` in controllers to check for specific scopes:

      plug :require_scope, "dns:write" when action in [:create, :update, :delete]

  """

  import Plug.Conn
  import Phoenix.Controller

  alias RouterosCm.ApiAuth
  alias RouterosCm.Accounts.Scope

  @doc """
  Authenticates the API request using a bearer token.

  Sets `conn.assigns.api_token` and `conn.assigns.current_scope` on success.
  Returns 401 Unauthorized on failure.
  """
  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, token} <- extract_token(conn),
         {:ok, api_token} <- ApiAuth.authenticate(token) do
      conn
      |> assign(:api_token, api_token)
      |> assign(:current_scope, build_scope(api_token))
    else
      {:error, :missing_token} ->
        conn
        |> put_status(:unauthorized)
        |> put_view(json: RouterosCmWeb.ErrorJSON)
        |> render("401.json", %{message: "Missing Authorization header"})
        |> halt()

      {:error, :invalid_token} ->
        conn
        |> put_status(:unauthorized)
        |> put_view(json: RouterosCmWeb.ErrorJSON)
        |> render("401.json", %{message: "Invalid or expired API token"})
        |> halt()
    end
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

  # Private helpers

  defp extract_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, String.trim(token)}
      ["bearer " <> token] -> {:ok, String.trim(token)}
      _ -> {:error, :missing_token}
    end
  end

  defp build_scope(api_token) do
    Scope.for_api_token(api_token)
  end
end
