defmodule Slidex.Polling.Option do
  use Ecto.Schema
  import Ecto.Changeset
  alias Slidex.Polling.Question

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "options" do
    field :position, :integer, default: 0
    field :body, :string
    field :is_correct, :boolean, default: false

    belongs_to :question, Question

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(option, attrs) do
    permitted = [:position, :body, :is_correct]
    required = [:body]

    option
    |> cast(attrs, permitted)
    |> validate_required(required)
    |> foreign_key_constraint(:question_id)
  end
end
