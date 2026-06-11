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

  @doc """
  Subscribes to the public room topic for a session, used by the presenter and
  participants for live lifecycle, question, and results events.
  """
  def subscribe_session(%Session{slug: slug}) do
    Phoenix.PubSub.subscribe(Slidex.PubSub, "session:#{slug}")
  end

  defp broadcast_to_session(%Session{slug: slug}, message) do
    Phoenix.PubSub.broadcast(Slidex.PubSub, "session:#{slug}", message)
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

  @doc """
  Looks up a session by its public slug, with no scope. Returns nil when there
  is no match. Used by the public join page.
  """
  def get_session_by_slug(slug) when is_binary(slug) do
    Session
    |> Repo.get_by(slug: slug)
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
         {:ok, closed} <-
           scope
           |> change_session(session, close_attrs(session))
           |> Repo.update() do
      broadcast_session(scope, {:closed, closed})
      broadcast_to_session(closed, {:state_changed, closed.state})
      {:ok, closed}
    else
      %Session{closed_at: %DateTime{}} -> {:ok, session}
      error -> error
    end
  end

  def reopen_session(%Scope{} = scope, %Session{} = session) do
    :ok = authorize(scope, session)

    with %Session{closed_at: %DateTime{}} <- session,
         {:ok, reopened} <-
           scope
           |> change_session(session, reopen_attrs(session))
           |> Repo.update() do
      broadcast_session(scope, {:reopened, reopened})
      broadcast_to_session(reopened, {:state_changed, reopened.state})
      {:ok, reopened}
    else
      %Session{closed_at: nil} -> {:ok, session}
      error -> error
    end
  end

  @doc """
  Starts a pending voting session, moving it to `:active` so it accepts votes.
  """
  def start_session(%Scope{} = scope, %Session{} = session) do
    :ok = authorize(scope, session)

    with %Session{state: :pending} <- session,
         {:ok, started} <-
           scope
           |> change_session(session, %{state: :active})
           |> Repo.update() do
      broadcast_to_session(started, {:state_changed, :active})
      {:ok, started}
    else
      %Session{} -> {:error, :invalid_transition}
      error -> error
    end
  end

  @doc """
  Points a session at the question the presenter is currently showing.
  """
  def set_current_question(%Scope{} = scope, %Session{} = session, %Question{} = question) do
    :ok = authorize(scope, session)

    with :ok <- ensure_question_in_session(session, question),
         {:ok, updated} <-
           scope
           |> change_session(session, %{current_question_id: question.id})
           |> Repo.update() do
      broadcast_to_session(updated, {:question_changed, question.id})
      {:ok, updated}
    end
  end

  # A survey keeps its :survey state when closed (it is tracked open or closed
  # by closed_at); a voting session moves through the :pending/:active/:ended
  # lifecycle.
  defp close_attrs(%Session{state: :survey}), do: %{closed_at: DateTime.utc_now()}
  defp close_attrs(%Session{}), do: %{closed_at: DateTime.utc_now(), state: :ended}

  defp reopen_attrs(%Session{state: :survey}), do: %{closed_at: nil}
  defp reopen_attrs(%Session{}), do: %{closed_at: nil, state: :active}

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

  @doc """
  Lists a session's poll questions with their options, with no scope. Used by
  the public join page for surveys, which show every question at once.
  """
  def list_session_questions(%Session{} = session) do
    options_query = from(o in Option, order_by: [asc: o.position, asc: o.inserted_at])

    Question
    |> where([q], q.poll_id == ^session.poll_id)
    |> order_by([q], asc: q.position, asc: q.inserted_at)
    |> preload(options: ^options_query)
    |> Repo.all()
  end

  @doc """
  Returns the participant's current choice per question as a map of
  `question_id => option_id`.
  """
  def list_participant_votes(%Session{} = session, %Participant{} = participant) do
    Vote
    |> where([v], v.session_id == ^session.id and v.participant_id == ^participant.id)
    |> select([v], {v.question_id, v.option_id})
    |> Repo.all()
    |> Map.new()
  end

  defp ensure_votable(%Session{state: state, closed_at: nil}) when state in [:active, :survey],
    do: :ok

  defp ensure_votable(%Session{}), do: {:error, :session_not_votable}

  defp ensure_question_in_session(%Session{poll_id: poll_id}, %Question{poll_id: poll_id}),
    do: :ok

  defp ensure_question_in_session(_session, _question), do: {:error, :question_not_in_session}

  defp ensure_option_in_question(%Question{id: id}, %Option{question_id: id}), do: :ok
  defp ensure_option_in_question(_question, _option), do: {:error, :option_not_in_question}
end
