defmodule Slidex.Repo.Migrations.CreateQuestions do
  use Ecto.Migration

  def change do
    create table(:questions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :position, :integer
      add :body, :string
      add :poll_id, references(:polls, on_delete: :nothing, type: :binary_id)
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:questions, [:user_id])

    create index(:questions, [:poll_id])
  end
end
