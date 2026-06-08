defmodule Slidex.Repo.Migrations.RemoveClosedAtFromPolls do
  use Ecto.Migration

  def change do
    alter table(:polls) do
      remove :closed_at
    end
  end
end
