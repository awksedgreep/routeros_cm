defmodule RouterosCm.Repo.Migrations.CreateAuditLogs do
  use Ecto.Migration

  def change do
    create table(:audit_logs) do
      add :user_id, references(:users, on_delete: :nilify_all)
      add :action, :string, null: false
      add :resource_type, :string, null: false
      add :resource_id, :integer
      add :details, :text
      add :success, :boolean, default: true, null: false
      add :ip_address, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:audit_logs, [:user_id])
    create index(:audit_logs, [:resource_type])
    create index(:audit_logs, [:action])
    create index(:audit_logs, [:success])
    create index(:audit_logs, [:inserted_at])
  end
end
