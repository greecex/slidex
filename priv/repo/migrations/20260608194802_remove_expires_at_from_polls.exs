defmodule Slidex.Repo.Migrations.RemoveExpiresAtFromPolls do
  use Ecto.Migration

  def change do
    alter table(:polls) do
      remove :expires_at
    end
  end
end
