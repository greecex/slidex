defmodule Slidex.Repo.Migrations.AddShowVoterChoicesToSessions do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add :show_voter_choices, :boolean, default: false, null: false
    end

    create index(:sessions, [:show_voter_choices])
  end
end
