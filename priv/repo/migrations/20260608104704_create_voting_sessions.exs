defmodule Slidex.Repo.Migrations.CreateSessions do
  use Ecto.Migration

  def change do
    create table(:sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string
      add :state, :string
      add :is_survey, :boolean, default: false, null: false

      add :poll_id, references(:polls, on_delete: :nothing, type: :binary_id), null: false
      add :current_question_id, references(:questions, on_delete: :nothing, type: :binary_id)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:sessions, [:poll_id])
    create index(:sessions, [:current_question_id])
  end
end
