defmodule Slidex.Repo.Migrations.AddShowDescriptionToSession do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add :show_description, :boolean, default: false, null: false
    end
  end
end
