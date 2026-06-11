defmodule Slidex.Repo.Migrations.AddShowResultsToSessionsAndCreateResults do
  use Ecto.Migration

  def change do
    # Allow the MC (poll owner) to toggle whether live results are visible to participants
    # for the current_question. Defaults to false (results hidden until MC enables).
    alter table(:sessions) do
      add :show_results, :boolean, default: false, null: false
    end

    create index(:sessions, [:show_results])

    # Stores each participant's choice of Option for a given Question within a Session.
    # Supports both authenticated users (user_id) and guest visitors (visitor_id persisted
    # via browser localStorage). Exactly one of user_id or visitor_id is present per row.
    # This enables deduplication, live tallies, and per-participant correctness scoring
    # for the leaderboard when any options have is_correct: true.
    create table(:results, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :session_id, references(:sessions, on_delete: :delete_all, type: :binary_id),
        null: false

      add :question_id, references(:questions, on_delete: :delete_all, type: :binary_id),
        null: false

      add :option_id, references(:options, on_delete: :delete_all, type: :binary_id), null: false

      # Exactly one of these two will be non-null for a given result row.
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id)
      add :visitor_id, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:results, [:session_id])
    create index(:results, [:question_id])
    create index(:results, [:option_id])
    create index(:results, [:user_id])
    create index(:results, [:visitor_id])

    # Enforce one vote per (session, question) per unique voter.
    # Partial indexes (Postgres) so NULLs don't collide across the two identity types.
    create unique_index(:results, [:session_id, :question_id, :user_id],
             where: "user_id IS NOT NULL",
             name: :results_session_question_user_unique
           )

    create unique_index(:results, [:session_id, :question_id, :visitor_id],
             where: "visitor_id IS NOT NULL",
             name: :results_session_question_visitor_unique
           )
  end
end
