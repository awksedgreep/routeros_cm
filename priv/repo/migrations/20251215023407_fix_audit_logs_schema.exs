defmodule RouterosCm.Repo.Migrations.FixAuditLogsSchema do
  use Ecto.Migration

  def change do
    # Clear existing audit logs and rebuild schema
    execute "DELETE FROM audit_logs", ""

    # Change resource_id from integer to string to support record names
    alter table(:audit_logs) do
      remove :resource_id
      remove :details
    end

    alter table(:audit_logs) do
      add :resource_id, :string
      add :details, :map
    end
  end
end
