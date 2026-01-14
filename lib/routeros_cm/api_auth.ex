defmodule RouterosCm.ApiAuth do
  @moduledoc """
  Context for API token authentication and management.
  """

  import Ecto.Query, warn: false
  alias RouterosCm.Repo
  alias RouterosCm.Accounts.ApiToken

  @doc """
  Lists all API tokens for a user.
  """
  def list_tokens(user_id) do
    ApiToken
    |> where([t], t.user_id == ^user_id)
    |> where([t], is_nil(t.revoked_at))
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
  end

  @doc """
  Lists all API tokens (admin function).
  """
  def list_all_tokens do
    ApiToken
    |> where([t], is_nil(t.revoked_at))
    |> order_by([t], desc: t.inserted_at)
    |> preload(:user)
    |> Repo.all()
  end

  @doc """
  Gets a single API token by ID.
  """
  def get_token(id), do: Repo.get(ApiToken, id)

  @doc """
  Gets a single API token by ID, raises if not found.
  """
  def get_token!(id), do: Repo.get!(ApiToken, id)

  @doc """
  Creates a new API token.

  Returns `{:ok, api_token}` where `api_token.token` contains the plain text token.
  The plain text token is only available immediately after creation.
  """
  def create_token(attrs \\ %{}) do
    %ApiToken{}
    |> ApiToken.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a new API token for a specific user.
  """
  def create_token_for_user(user, attrs) do
    attrs
    |> stringify_keys()
    |> Map.put("user_id", user.id)
    |> create_token()
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  @doc """
  Updates an API token's metadata.
  """
  def update_token(%ApiToken{} = token, attrs) do
    token
    |> ApiToken.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Revokes an API token. Revoked tokens cannot be used for authentication.

  Accepts either an `%ApiToken{}` struct or an integer ID.
  """
  def revoke_token(%ApiToken{} = token) do
    token
    |> ApiToken.revoke_changeset()
    |> Repo.update()
  end

  def revoke_token(id) when is_integer(id) do
    case get_token(id) do
      nil -> {:error, :not_found}
      token -> revoke_token(token)
    end
  end

  @doc """
  Deletes an API token permanently.
  """
  def delete_token(%ApiToken{} = token) do
    Repo.delete(token)
  end

  @doc """
  Authenticates an API request using a bearer token.

  Returns `{:ok, api_token}` if valid, `{:error, reason}` otherwise.
  Also updates the last_used_at timestamp on successful authentication.
  """
  def authenticate(token) when is_binary(token) do
    # Query all active tokens and verify against each
    # This is necessary because we use bcrypt hashing
    query =
      from t in ApiToken,
        where: is_nil(t.revoked_at),
        preload: [:user]

    Repo.all(query)
    |> Enum.find(fn api_token ->
      ApiToken.verify_token(api_token, token) and ApiToken.valid?(api_token)
    end)
    |> case do
      nil ->
        {:error, :invalid_token}

      api_token ->
        touch_token(api_token)
        {:ok, api_token}
    end
  end

  def authenticate(_), do: {:error, :invalid_token}

  @doc """
  Checks if a token has the required scope.
  """
  def has_scope?(%ApiToken{} = token, scope) do
    ApiToken.has_scope?(token, scope)
  end

  @doc """
  Returns the list of valid scopes.
  """
  def valid_scopes, do: ApiToken.valid_scopes()

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking token changes.
  """
  def change_token(%ApiToken{} = token, attrs \\ %{}) do
    ApiToken.changeset(token, attrs)
  end

  # Private helpers

  defp touch_token(api_token) do
    api_token
    |> ApiToken.touch_changeset()
    |> Repo.update()
  end
end
