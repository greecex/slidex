defmodule Slidex.Repo.Migrations.AddUlidSlugToPolls do
  use Ecto.Migration

  def change do
    alter table(:polls) do
      add :slug, :citext, null: false
    end

    create unique_index(:polls, [:slug])
  end
end
