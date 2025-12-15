defmodule RouterosCm.Cluster.Node do
  @moduledoc """
  Schema for CHR (Cloud Hosted Router) nodes in the cluster.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias RouterosCm.Vault

  schema "nodes" do
    field :name, :string
    field :host, :string
    field :port, :integer, default: 80

    # Plain text fields (deprecated, kept for migration compatibility)
    field :username, :string
    field :password, :string, virtual: true, redact: true

    # Encrypted credential storage
    field :username_encrypted, :string
    field :password_encrypted, :string, redact: true

    field :status, :string, default: "unknown"
    field :last_seen_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(name host)a
  @optional_fields ~w(port status last_seen_at)a
  @credential_fields ~w(username password)a

  @doc """
  Changeset for creating a new node.
  Automatically encrypts username and password.
  """
  def changeset(node, attrs) do
    node
    |> cast(attrs, @required_fields ++ @optional_fields ++ @credential_fields)
    |> validate_required(@required_fields ++ @credential_fields)
    |> validate_length(:name, min: 1, max: 100)
    |> validate_format(:host, ~r/^[\w.-]+$/, message: "must be a valid hostname or IP address")
    |> validate_number(:port, greater_than: 0, less_than_or_equal_to: 65535)
    |> unique_constraint(:name)
    |> unique_constraint([:host, :port])
    |> encrypt_credentials()
  end

  @doc """
  Returns decrypted username for the node.
  Falls back to plain username field for migration compatibility.
  """
  def get_username(%__MODULE__{username_encrypted: encrypted}) when is_binary(encrypted) do
    Vault.decrypt!(encrypted)
  end

  def get_username(%__MODULE__{username: username}), do: username

  @doc """
  Returns decrypted password for the node.
  Falls back to plain password field for migration compatibility.
  """
  def get_password(%__MODULE__{password_encrypted: encrypted}) when is_binary(encrypted) do
    Vault.decrypt!(encrypted)
  end

  def get_password(%__MODULE__{password: password}), do: password

  # Encrypts username and password, storing in encrypted fields
  defp encrypt_credentials(changeset) do
    changeset
    |> encrypt_field(:username, :username_encrypted)
    |> encrypt_field(:password, :password_encrypted)
  end

  defp encrypt_field(changeset, source_field, target_field) do
    case get_change(changeset, source_field) do
      nil ->
        changeset

      value ->
        changeset
        |> put_change(target_field, Vault.encrypt!(value))
        # Clear the plain text field after encrypting
        |> put_change(source_field, nil)
    end
  end
end
