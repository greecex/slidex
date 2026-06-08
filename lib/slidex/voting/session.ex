defmodule Slidex.Voting.Session do
  use Ecto.Schema
  import Ecto.Changeset
  alias Slidex.Campaigns.Poll
  alias Slidex.Polling.Question

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "sessions" do
    field :title, :string
    field :state, Ecto.Enum, values: [:pending, :active, :ended]
    field :is_survey, :boolean, default: false

    belongs_to :poll, Poll
    belongs_to :current_question, Question

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(session, attrs) do
    permitted = [:title, :state, :is_survey]
    required = []

    session
    |> cast(attrs, permitted)
    |> validate_required(required)
    |> maybe_set_title()
    |> validate_length(:title, max: 50)
  end

  defp maybe_set_title(%Ecto.Changeset{} = changeset) do
    title = get_field(changeset, :title, "")

    if String.trim(title) == "",
      do: put_change(changeset, :title, to_string(Date.utc_today())),
      else: changeset
  end
end
