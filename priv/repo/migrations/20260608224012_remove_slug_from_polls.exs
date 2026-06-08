defmodule Slidex.Repo.Migrations.RemoveSlugFromPolls do
  use Ecto.Migration

  def change do
    alter table(:polls) do
      remove :slug
    end
  end
end
