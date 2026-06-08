defmodule Slidex.Repo.Migrations.AddDescriptionToPolls do
  use Ecto.Migration

  def change do
    alter table(:polls) do
      add :description, :string
    end

    alter table(:sessions) do
      add :show_poll_description, :boolean, default: false, null: false
    end
  end
end
