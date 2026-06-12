defmodule Slidex.Voting.Vote do
  use Ecto.Schema
  import Ecto.Changeset
  alias Slidex.Polling.{Option, Question}
  alias Slidex.Voting.{Participant, Session}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "votes" do
    belongs_to :session, Session
    belongs_to :question, Question
    belongs_to :option, Option
    belongs_to :participant, Participant

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(vote, attrs \\ %{}) do
    # All fields are foreign keys set on the struct by the context. Nothing is
    # cast from user input; the changeset only surfaces the database constraints.
    vote
    |> cast(attrs, [])
    |> unique_constraint([:session_id, :question_id, :participant_id])
    |> foreign_key_constraint(:session_id)
    |> foreign_key_constraint(:question_id)
    |> foreign_key_constraint(:option_id)
    |> foreign_key_constraint(:participant_id)
  end
end
