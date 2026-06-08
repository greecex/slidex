defmodule Slidex.Repo.Migrations.DropIsSurveyFromSessions do
  use Ecto.Migration

  def change do
    drop_if_exists index(:sessions, [:is_survey])

    alter table(:sessions) do
      remove :is_survey
    end
  end
end
