defmodule RouterosCm.Audit.Log do
  @moduledoc """
  Schema for audit logs tracking all cluster operations.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias RouterosCm.Accounts.User

  schema "audit_logs" do
    belongs_to :user, User
    field :action, :string
    field :resource_type, :string
    field :resource_id, :string
    field :details, :map
    field :success, :boolean, default: true
    field :error_message, :string, virtual: true
    field :ip_address, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(log, attrs) do
    log
    |> cast(attrs, [
      :user_id,
      :action,
      :resource_type,
      :resource_id,
      :details,
      :success,
      :ip_address
    ])
    |> validate_required([:action, :resource_type])
    |> maybe_add_error_to_details(attrs)
  end

  defp maybe_add_error_to_details(changeset, %{error_message: error}) when not is_nil(error) do
    details = get_field(changeset, :details) || %{}
    put_change(changeset, :details, Map.put(details, "error", error))
  end

  defp maybe_add_error_to_details(changeset, _attrs), do: changeset
end
