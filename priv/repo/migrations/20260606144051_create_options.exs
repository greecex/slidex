defmodule Slidex.Repo.Migrations.CreateOptions do
  use Ecto.Migration

  def change do
    create table(:options, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :position, :integer
      add :body, :string
      add :is_correct, :boolean, default: false, null: false
      add :question_id, references(:questions, on_delete: :delete_all, type: :binary_id)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:options, [:question_id])
  end
end
