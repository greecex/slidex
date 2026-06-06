defmodule Slidex.Polling.Question do
  use Ecto.Schema
  import Ecto.Changeset
  alias Slidex.Campaigns.Poll
  alias Slidex.Polling.Option

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "questions" do
    field :position, :integer, default: 0
    field :body, :string

    belongs_to :poll, Poll
    has_many :options, Option, on_delete: :delete_all

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(question, attrs) do
    permitted = [:position, :body]
    required = [:body]

    question
    |> cast(attrs, permitted)
    |> validate_required(required)
    |> foreign_key_constraint(:poll_id)
    |> cast_assoc(:options)
  end
end
