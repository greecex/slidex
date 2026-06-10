defmodule Slidex.Repo.Migrations.CreateVotingParticipantsAndVotes do
  use Ecto.Migration

  def change do
    create table(:participants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :display_name, :string
      add :token, :string, null: false

      add :session_id, references(:sessions, on_delete: :delete_all, type: :binary_id),
        null: false

      add :user_id, references(:users, on_delete: :nilify_all, type: :binary_id)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:participants, [:session_id, :token])
    create index(:participants, [:user_id])

    create table(:votes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :session_id, references(:sessions, on_delete: :delete_all, type: :binary_id),
        null: false

      add :question_id, references(:questions, on_delete: :delete_all, type: :binary_id),
        null: false

      add :option_id, references(:options, on_delete: :delete_all, type: :binary_id), null: false

      add :participant_id, references(:participants, on_delete: :delete_all, type: :binary_id),
        null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:votes, [:session_id, :question_id, :participant_id])
    create index(:votes, [:session_id, :question_id])
    create index(:votes, [:option_id])
  end
end
