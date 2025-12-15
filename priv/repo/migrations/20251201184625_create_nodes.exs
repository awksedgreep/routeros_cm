defmodule RouterosCm.Repo.Migrations.CreateNodes do
  use Ecto.Migration

  def change do
    create table(:nodes) do
      add :name, :string, null: false
      add :host, :string, null: false
      add :port, :integer, default: 443
      add :username, :string
      add :password, :string
      add :username_encrypted, :string
      add :password_encrypted, :string
      add :status, :string, default: "unknown"
      add :last_seen_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:nodes, [:name])
    create unique_index(:nodes, [:host, :port])
  end
end
