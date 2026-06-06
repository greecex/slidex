defmodule Slidex.Repo.Migrations.CreateQuestions do
  use Ecto.Migration

  def change do
    create table(:questions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :position, :integer, default: 0
      add :body, :string, null: false
      add :poll_id, references(:polls, on_delete: :nothing, type: :binary_id)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:questions, [:poll_id])
  end
end
