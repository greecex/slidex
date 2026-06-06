defmodule Slidex.Repo.Migrations.CreatePolls do
  use Ecto.Migration

  def change do
    create table(:polls, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string
      add :is_public, :boolean, default: false, null: false
      add :access_code, :string
      add :expires_at, :utc_datetime
      add :closed_at, :utc_datetime
      add :archived_at, :utc_datetime_usec
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:polls, [:user_id])
  end
end
