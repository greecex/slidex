defmodule Slidex.Voting.Result do
  @moduledoc """
  Records a single vote: which Option a participant (authenticated User or guest visitor)
  selected for a particular Question inside a voting Session.

  Used for:
  - Preventing double-voting / vote changes on the current question.
  - Computing live per-option tallies when the MC enables show_results.
  - Building leaderboards of correct answers (when any Option.is_correct is true).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Slidex.Accounts.User
  alias Slidex.Polling.{Option, Question}
  alias Slidex.Voting.Session

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "results" do
    belongs_to :session, Session
    belongs_to :question, Question
    belongs_to :option, Option
    belongs_to :user, User

    # Opaque identifier generated in the browser and stored in localStorage for guests.
    # Combined with session+question it provides stable identity for non-logged-in participants.
    field :visitor_id, :string

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for casting (or updating) a vote.

  Exactly one of user_id or visitor_id must be provided. The combination of
  (session_id, question_id, user_id) or (session_id, question_id, visitor_id)
  must be unique (enforced at the database level with partial indexes).

  ## Examples

      iex> alias Slidex.Voting.Result
      iex> changeset = Result.changeset(%Result{}, %{
      ...>   session_id: "11111111-1111-1111-1111-111111111111",
      ...>   question_id: "22222222-2222-2222-2222-222222222222",
      ...>   option_id: "33333333-3333-3333-3333-333333333333",
      ...>   user_id: "44444444-4444-4444-4444-444444444444"
      ...> })
      iex> changeset.valid?
      true

      iex> alias Slidex.Voting.Result
      iex> changeset = Result.changeset(%Result{}, %{
      ...>   session_id: "11111111-1111-1111-1111-111111111111",
      ...>   question_id: "22222222-2222-2222-2222-222222222222",
      ...>   option_id: "33333333-3333-3333-3333-333333333333",
      ...>   visitor_id: "guest-abc123"
      ...> })
      iex> changeset.valid?
      true
  """
  def changeset(result, attrs) do
    permitted = [:session_id, :question_id, :option_id, :user_id, :visitor_id]

    result
    |> cast(attrs, permitted)
    |> validate_required([:session_id, :question_id, :option_id])
    |> validate_voter_identity()
    |> foreign_key_constraint(:session_id)
    |> foreign_key_constraint(:question_id)
    |> foreign_key_constraint(:option_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:user_id,
      name: :results_session_question_user_unique,
      message: "has already voted on this question"
    )
    |> unique_constraint(:visitor_id,
      name: :results_session_question_visitor_unique,
      message: "has already voted on this question"
    )
  end

  defp validate_voter_identity(changeset) do
    user_id = get_field(changeset, :user_id)
    visitor_id = get_field(changeset, :visitor_id)

    cond do
      is_binary(user_id) and is_binary(visitor_id) ->
        add_error(changeset, :user_id, "cannot vote as both a user and a visitor")

      is_binary(user_id) or is_binary(visitor_id) ->
        changeset

      true ->
        add_error(changeset, :user_id, "must identify as either a logged-in user or a visitor")
    end
  end
end
