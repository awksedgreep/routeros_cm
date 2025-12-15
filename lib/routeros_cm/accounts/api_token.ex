defmodule RouterosCm.Accounts.ApiToken do
  @moduledoc """
  Schema for API tokens used for service-to-service authentication.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @valid_scopes ~w(
    nodes:read nodes:write
    dns:read dns:write
    tunnels:read tunnels:write
    wireguard:read wireguard:write
    users:read users:write
    audit:read
  )

  schema "api_tokens" do
    field :name, :string
    field :token, :string, virtual: true, redact: true
    field :token_hash, :string, redact: true
    field :description, :string
    field :scopes, {:array, :string}, default: []
    field :last_used_at, :utc_datetime
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime

    belongs_to :user, RouterosCm.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new API token.
  """
  def changeset(api_token, attrs) do
    api_token
    |> cast(attrs, [:name, :description, :scopes, :expires_at, :user_id])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 500)
    |> validate_scopes()
    |> put_token()
  end

  @doc """
  Changeset for updating token metadata (not the token itself).
  """
  def update_changeset(api_token, attrs) do
    api_token
    |> cast(attrs, [:name, :description, :scopes, :expires_at])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 500)
    |> validate_scopes()
  end

  @doc """
  Changeset for revoking a token.
  """
  def revoke_changeset(api_token) do
    change(api_token, %{revoked_at: DateTime.utc_now() |> DateTime.truncate(:second)})
  end

  @doc """
  Changeset for updating last_used_at timestamp.
  """
  def touch_changeset(api_token) do
    change(api_token, %{last_used_at: DateTime.utc_now() |> DateTime.truncate(:second)})
  end

  @doc """
  Returns the list of valid scopes.
  """
  def valid_scopes, do: @valid_scopes

  @doc """
  Verifies a token against the stored hash.
  """
  def verify_token(api_token, token) do
    Bcrypt.verify_pass(token, api_token.token_hash)
  end

  @doc """
  Checks if a token has the required scope.
  """
  def has_scope?(%__MODULE__{scopes: scopes}, required_scope) do
    required_scope in scopes or has_wildcard_scope?(scopes, required_scope)
  end

  @doc """
  Checks if the token is expired or revoked.
  """
  def valid?(%__MODULE__{revoked_at: revoked_at, expires_at: expires_at}) do
    not revoked?(revoked_at) and not expired?(expires_at)
  end

  # Private helpers

  defp validate_scopes(changeset) do
    validate_change(changeset, :scopes, fn :scopes, scopes ->
      invalid = Enum.reject(scopes, &(&1 in @valid_scopes))

      if invalid == [] do
        []
      else
        [scopes: "contains invalid scopes: #{Enum.join(invalid, ", ")}"]
      end
    end)
  end

  defp put_token(changeset) do
    if changeset.valid? do
      token = generate_token()
      token_hash = Bcrypt.hash_pwd_salt(token)

      changeset
      |> put_change(:token, token)
      |> put_change(:token_hash, token_hash)
    else
      changeset
    end
  end

  defp generate_token do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end

  defp has_wildcard_scope?(scopes, required_scope) do
    [resource, _action] = String.split(required_scope, ":")
    "#{resource}:write" in scopes and String.ends_with?(required_scope, ":read")
  end

  defp revoked?(nil), do: false
  defp revoked?(_), do: true

  defp expired?(nil), do: false

  defp expired?(expires_at) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end
end
