defmodule Slidex.Polling.Option do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "options" do
    field :position, :integer
    field :body, :string
    field :is_correct, :boolean, default: false
    field :question_id, :binary_id
    field :user_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(option, attrs, user_scope) do
    option
    |> cast(attrs, [:position, :body, :is_correct])
    |> validate_required([:position, :body, :is_correct])
    |> put_change(:user_id, user_scope.user.id)
  end
end
