defmodule Slidex.Voting do
  import Ecto.Query
  import Slidex.Preloader
  import Slidex.Authorization

  alias Slidex.{Repo, Preloader}
  alias Slidex.Accounts.Scope
  alias Slidex.Campaigns.Poll
  alias Slidex.Polling.{Question, Option}
  alias __MODULE__.{Session, Participant, Vote, Tally}

  def subscribe_sessions(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(Slidex.PubSub, "user:#{key}:sessions")
  end

  defp broadcast_session(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(Slidex.PubSub, "user:#{key}:sessions", message)
  end

  def list_sessions(%Scope{} = scope) do
    scope
    |> query_sessions()
    |> Repo.all()
    |> Preloader.with_preloads()
  end

  def list_sessions(%Scope{} = scope, %Poll{} = poll) do
    scope
    |> query_sessions()
    |> where([s, p], s.poll_id == ^poll.id)
    |> Repo.all()
    |> Preloader.with_preloads()
  end

  defp query_sessions(scope) do
    Session
    |> join(:inner, [s], p in assoc(s, :poll))
    |> where([_s, p], p.user_id == ^scope.user.id)
    |> order_by([s], desc: s.updated_at)
  end

  def get_session!(%Scope{} = scope, id) do
    Session
    |> join(:inner, [s], p in assoc(s, :poll))
    |> where([s, p], p.user_id == ^scope.user.id)
    |> Repo.get!(id)
    |> Preloader.with_preloads()
  end

  def create_session(%Scope{} = scope, %Poll{} = poll, attrs) do
    :ok = authorize(scope, poll)

    %Session{poll_id: poll.id}
    |> Session.changeset(attrs)
    |> Repo.insert()
    |> with_preloads
  end

  def update_session(%Scope{} = scope, %Session{} = session, attrs) do
    :ok = authorize(scope, session)

    with {:ok, session = %Session{}} <-
           session
           |> Session.changeset(attrs)
           |> Repo.update() do
      broadcast_session(scope, {:updated, session})
      {:ok, session}
    end
  end

  def delete_session(%Scope{} = scope, %Session{} = session) do
    :ok = authorize(scope, session)

    Repo.delete(session)
  end

  def change_session(%Scope{} = scope, %Session{} = session, attrs \\ %{}) do
    # Only authorize if the session already belongs to a poll,
    # i.e. when we are editing an existing session, instead of creating a new session
    if session.id do
      :ok = authorize(scope, session)
    end

    Session.changeset(session, attrs)
  end

  def close_session(%Scope{} = scope, %Session{} = session) do
    :ok = authorize(scope, session)

    with %Session{closed_at: nil} <- session,
         attrs = %{closed_at: DateTime.utc_now()},
         {:ok, closed} <-
           scope
           |> change_session(session, attrs)
           |> Repo.update() do
      broadcast_session(scope, {:closed, closed})
      {:ok, closed}
    else
      %Session{closed_at: %DateTime{}} -> {:ok, session}
      error -> error
    end
  end

  def reopen_session(%Scope{} = scope, %Session{} = session) do
    :ok = authorize(scope, session)

    with %Session{closed_at: %DateTime{}} <- session,
         attrs = %{closed_at: nil},
         {:ok, reopened} <-
           scope
           |> change_session(session, attrs)
           |> Repo.update() do
      broadcast_session(scope, {:reopened, reopened})
      {:ok, reopened}
    else
      %Session{closed_at: nil} -> {:ok, session}
      error -> error
    end
  end

  # Participants and votes are part of the public, guest-facing path, so these
  # functions take a session and a participant rather than a %Scope{}.

  def find_or_create_participant(%Session{} = session, token, attrs \\ %{})
      when is_binary(token) do
    case Repo.get_by(Participant, session_id: session.id, token: token) do
      %Participant{} = participant ->
        {:ok, participant}

      nil ->
        %Participant{session_id: session.id, token: token, user_id: Map.get(attrs, :user_id)}
        |> Participant.changeset(attrs)
        |> Repo.insert()
    end
  end

  def cast_vote(
        %Session{} = session,
        %Participant{} = participant,
        %Question{} = question,
        %Option{} = option
      ) do
    with :ok <- ensure_votable(session),
         :ok <- ensure_question_in_session(session, question),
         :ok <- ensure_option_in_question(question, option) do
      %Vote{
        session_id: session.id,
        question_id: question.id,
        option_id: option.id,
        participant_id: participant.id
      }
      |> Vote.changeset()
      |> Repo.insert(
        on_conflict: {:replace, [:option_id, :updated_at]},
        conflict_target: [:session_id, :question_id, :participant_id],
        returning: true
      )
    end
  end

  def tally(%Session{} = session, %Question{} = question) do
    Vote
    |> where([v], v.session_id == ^session.id and v.question_id == ^question.id)
    |> Repo.all()
    |> Tally.by_option()
  end

  defp ensure_votable(%Session{state: state}) when state in [:active, :survey], do: :ok
  defp ensure_votable(%Session{}), do: {:error, :session_not_votable}

  defp ensure_question_in_session(%Session{poll_id: poll_id}, %Question{poll_id: poll_id}),
    do: :ok

  defp ensure_question_in_session(_session, _question), do: {:error, :question_not_in_session}

  defp ensure_option_in_question(%Question{id: id}, %Option{question_id: id}), do: :ok
  defp ensure_option_in_question(_question, _option), do: {:error, :option_not_in_question}
end
