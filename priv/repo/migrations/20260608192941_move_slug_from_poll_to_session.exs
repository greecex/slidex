defmodule Slidex.Repo.Migrations.MoveSlugFromPollToSession do
  use Ecto.Migration

  def change do
    drop_if_exists index(:polls, [:slug])

    alter table(:sessions) do
      add :slug, :citext, null: false
    end
  end
end
