defmodule RouterosCm.Repo.Migrations.FixAuditLogsSchema do
  use Ecto.Migration

  def change do
    # SQLite doesn't support ALTER COLUMN, so we recreate the table
    # First, drop all existing audit logs (they were just errors anyway)
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

    # Note: SQLite creates columns as nullable by default unless specified otherwise
    # The original migration didn't add NOT NULL to user_id, so it should already be nullable
  end
end
