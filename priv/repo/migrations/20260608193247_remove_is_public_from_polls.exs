defmodule Slidex.Repo.Migrations.RemoveIsPublicFromPolls do
  use Ecto.Migration

  def change do
    alter table(:polls) do
      remove :is_public
    end
  end
end
