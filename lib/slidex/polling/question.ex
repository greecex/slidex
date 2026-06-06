defmodule Slidex.Polling.Question do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "questions" do
    field :position, :integer
    field :body, :string
    field :poll_id, :binary_id
    field :user_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(question, attrs, user_scope) do
    question
    |> cast(attrs, [:position, :body])
    |> validate_required([:position, :body])
    |> put_change(:user_id, user_scope.user.id)
  end
end
