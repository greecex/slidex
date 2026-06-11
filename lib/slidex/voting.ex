defmodule Slidex.Voting do
  import Ecto.Query
  import Slidex.Preloader
  import Slidex.Authorization

  alias Slidex.{Repo, Preloader}
  alias Slidex.Accounts.Scope
  alias __MODULE__.{Result, Session}
  alias Slidex.Campaigns.Poll
  alias Slidex.Polling.{Option, Question}

  def subscribe_sessions(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(Slidex.PubSub, "user:#{key}:sessions")
  end

  defp broadcast_session(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(Slidex.PubSub, "user:#{key}:sessions", message)
  end

  # --- Per-session (public) PubSub for the participant + MC LiveView ---

  @doc """
  Subscribes the current process to real-time updates for the voting session
  identified by `slug`. Used by VoteLive so everyone sees the same current
  question, live results toggles, state changes, and participant presence.
  """
  def subscribe_to_session(slug) when is_binary(slug) do
    Phoenix.PubSub.subscribe(Slidex.PubSub, "voting:session:#{slug}")
  end

  defp broadcast_to_session(slug, message) when is_binary(slug) do
    Phoenix.PubSub.broadcast(Slidex.PubSub, "voting:session:#{slug}", message)
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

  @doc """
  Returns a list of currently ongoing (active, open) voting sessions for the public home page.
  """
  def list_ongoing_sessions do
    now = DateTime.utc_now()

    Session
    |> where([s], s.state == :active)
    |> where([s], is_nil(s.closed_at))
    |> join(:inner, [s], p in assoc(s, :poll))
    |> where([s, p], is_nil(p.archived_at))
    |> where([s], is_nil(s.expires_at) or s.expires_at > ^now)
    |> preload([s, p], poll: p)
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
      broadcast_to_session(reopened.slug, {:reopened, reopened})
      {:ok, reopened}
    else
      %Session{closed_at: nil} -> {:ok, session}
      error -> error
    end
  end

  # --- Public (no scope) access for the /vote/:slug LiveView ---

  @doc """
  Fetches a Session by its public ULID slug.

  Preloads the poll and the current_question (with its options) so the
  VoteLive can render without extra queries in the common case.

  Returns nil when not found.
  """
  def get_session_by_slug(slug) when is_binary(slug) do
    # Citext column makes lookup case-insensitive, but we normalize the
    # returned slug to lowercase so that all generated /vote/ URLs use
    # lowercase ULIDs (as requested).
    case Session |> Repo.get_by(slug: slug) do
      nil ->
        nil

      %Session{} = session ->
        session = %{session | slug: String.downcase(session.slug)}
        Preloader.with_preloads(session)
    end
  end

  @doc """
  Same as get_session_by_slug/1 but raises Ecto.NoResultsError if missing.
  """
  def get_session_by_slug!(slug) when is_binary(slug) do
    case get_session_by_slug(slug) do
      nil -> raise Ecto.NoResultsError, queryable: Session
      session -> session
    end
  end

  @doc """
  Returns whether a participant (logged in or guest) is currently allowed to
  view the current question and cast a vote.

  Expects `session` to have its `:poll` preloaded (as returned by the
  get_session_by_slug* functions and the LiveView mount).

  A session is open for voting when all of the following are true:
  - state is :active (not :pending or :ended, and not a :survey)
  - closed_at is nil
  - expires_at is nil or still in the future
  - the parent Poll has not been archived

  ## Examples

      iex> alias Slidex.Voting.Session
      iex> alias Slidex.Campaigns.Poll
      iex> s = %Session{state: :active, closed_at: nil, expires_at: nil, poll: %Poll{archived_at: nil}}
      iex> Slidex.Voting.voting_open?(s)
      true

      iex> alias Slidex.Voting.Session
      iex> alias Slidex.Campaigns.Poll
      iex> s = %Session{state: :pending, closed_at: nil, expires_at: nil, poll: %Poll{archived_at: nil}}
      iex> Slidex.Voting.voting_open?(s)
      false
  """
  def voting_open?(%Session{state: :active, closed_at: nil} = session) do
    poll = Map.get(session, :poll) || %Poll{}

    expired? =
      case session.expires_at do
        nil -> false
        dt -> DateTime.compare(dt, DateTime.utc_now()) == :lt
      end

    archived? = not is_nil(poll.archived_at)

    not expired? and not archived?
  end

  def voting_open?(_other), do: false

  # --- MC controls (require Scope + ownership) ---

  @doc """
  Transitions a pending voting session to :active so participants can vote.

  Only the poll owner (MC) may call this. Idempotent if already active.
  Broadcasts on both the owner topic and the public session topic.
  """
  def start_session(%Scope{} = scope, %Session{} = session) do
    :ok = authorize(scope, session)

    if session.state == :pending do
      update_state_and_broadcast(scope, session, :active)
    else
      {:ok, session}
    end
  end

  @doc """
  Transitions an active session to :ended. Participants can no longer vote,
  but the MC can still move between questions and show results for review
  with new cohorts later (the session is not auto-closed).
  """
  def end_session(%Scope{} = scope, %Session{} = session) do
    :ok = authorize(scope, session)

    if session.state == :active do
      update_state_and_broadcast(scope, session, :ended)
    else
      {:ok, session}
    end
  end

  defp update_state_and_broadcast(%Scope{} = scope, %Session{} = session, new_state) do
    attrs = %{state: new_state}

    with {:ok, updated} <-
           scope
           |> change_session(session, attrs)
           |> Repo.update() do
      updated = Preloader.with_preloads(updated)
      broadcast_session(scope, {:updated, updated})
      broadcast_to_session(updated.slug, {:state_changed, updated})
      {:ok, updated}
    end
  end

  @doc """
  Sets which Question the entire session (all current participants) is looking at.

  Only the owner of the poll may do this. The question must belong to the
  same poll. Broadcasts the change so every connected VoteLive switches
  synchronously.
  """
  def set_current_question(%Scope{} = scope, %Session{} = session, %Question{} = question) do
    :ok = authorize(scope, session)

    if question.poll_id == session.poll_id do
      attrs = %{current_question_id: question.id}

      with {:ok, updated} <-
             scope
             |> change_session(session, attrs)
             |> Repo.update() do
        updated = Preloader.with_preloads(updated)
        broadcast_session(scope, {:updated, updated})
        broadcast_to_session(updated.slug, {:current_question_changed, updated})
        {:ok, updated}
      end
    else
      {:error, :question_belongs_to_different_poll}
    end
  end

  @doc """
  Toggles whether live results (tallies) for the current_question are shown
  to all participants in the VoteLive.

  Only the MC (poll owner) can toggle this. The value is persisted on the
  session so it survives reconnects and page reloads.
  """
  def toggle_show_results(%Scope{} = scope, %Session{} = session) do
    :ok = authorize(scope, session)

    attrs = %{show_results: not session.show_results}

    with {:ok, updated} <-
           scope
           |> change_session(session, attrs)
           |> Repo.update() do
      updated = Preloader.with_preloads(updated)
      broadcast_session(scope, {:updated, updated})
      broadcast_to_session(updated.slug, {:show_results_toggled, updated})
      {:ok, updated}
    end
  end

  @doc """
  Toggles whether non-MC participants can see which voters (by identicon) chose each option
  for the current question (when results are visible).
  The MC always sees voter choices in their view, regardless of this setting.
  """
  def toggle_voter_choices(%Scope{} = scope, %Session{} = session) do
    :ok = authorize(scope, session)

    attrs = %{show_voter_choices: not session.show_voter_choices}

    with {:ok, updated} <-
           scope
           |> change_session(session, attrs)
           |> Repo.update() do
      updated = Preloader.with_preloads(updated)
      broadcast_session(scope, {:updated, updated})
      broadcast_to_session(updated.slug, {:voter_choices_toggled, updated})
      {:ok, updated}
    end
  end

  @doc """
  Allows the MC to restart a previously ended voting session (sets state back to :active).
  Participants can then vote again on the current (or newly chosen) question.
  """
  def restart_voting(%Scope{} = scope, %Session{} = session) do
    :ok = authorize(scope, session)

    if session.state == :ended do
      attrs = %{state: :active}

      with {:ok, restarted} <-
             scope
             |> change_session(session, attrs)
             |> Repo.update() do
        restarted = Preloader.with_preloads(restarted)
        broadcast_session(scope, {:updated, restarted})
        broadcast_to_session(restarted.slug, {:state_changed, restarted})
        {:ok, restarted}
      end
    else
      {:ok, session}
    end
  end

  @doc """
  Clears all votes/results for the session. Only the MC can do this.
  Useful for reusing the same session with a new cohort without old data.
  """
  def reset_votes(%Scope{} = scope, %Session{} = session) do
    :ok = authorize(scope, session)

    from(r in Result, where: r.session_id == ^session.id)
    |> Repo.delete_all()

    broadcast_to_session(session.slug, {:votes_reset, session.id})
    {:ok, session}
  end

  # --- Voting (participants + MC) ---

  @doc """
  Records (or updates) the participant's choice of Option for the session's
  current question.

  `identity` must be either `%{user_id: binary}` for logged-in users or
  `%{visitor_id: binary}` for guests (the value comes from browser
  localStorage via a JS hook).

  Only allowed while `voting_open?/1` is true and the option belongs to the
  current question. On success the change is broadcast so all clients can
  update live tallies (when visible).

  Returns `{:ok, %Result{}}` or `{:error, reason}`.
  """
  def cast_vote(%Session{} = session, %Option{} = option, identity)
      when is_map(identity) do
    cond do
      not voting_open?(session) ->
        {:error, :voting_closed}

      is_nil(session.current_question_id) ->
        {:error, :no_current_question}

      option.question_id != session.current_question_id ->
        {:error, :not_current_question}

      true ->
        do_cast_vote(session, option, identity)
    end
  end

  defp do_cast_vote(session, option, %{user_id: user_id} = _identity)
       when is_binary(user_id) do
    upsert_result(session, option, %{user_id: user_id})
  end

  defp do_cast_vote(session, option, %{visitor_id: visitor_id} = _identity)
       when is_binary(visitor_id) do
    upsert_result(session, option, %{visitor_id: visitor_id})
  end

  defp do_cast_vote(_session, _option, _identity), do: {:error, :invalid_identity}

  defp upsert_result(session, option, identity_clause) do
    voter_dynamic = voter_dynamic(identity_clause)

    existing =
      Result
      |> where([r], r.session_id == ^session.id and r.question_id == ^option.question_id)
      |> where(^voter_dynamic)
      |> Repo.one()

    changeset_params =
      Map.merge(
        %{session_id: session.id, question_id: option.question_id, option_id: option.id},
        identity_clause
      )

    result =
      if existing do
        existing
        |> Result.changeset(changeset_params)
        |> Repo.update()
      else
        %Result{}
        |> Result.changeset(changeset_params)
        |> Repo.insert()
      end

    case result do
      {:ok, saved} ->
        broadcast_to_session(session.slug, {:vote_cast, session.id, option.question_id})
        # For global live vote count on home
        Phoenix.PubSub.broadcast(Slidex.PubSub, "global:votes", :vote_cast)
        {:ok, saved}

      error ->
        error
    end
  end

  defp voter_dynamic(%{user_id: uid}), do: dynamic([r], r.user_id == ^uid)
  defp voter_dynamic(%{visitor_id: vid}), do: dynamic([r], r.visitor_id == ^vid)

  # --- Pure query helpers and computations (great for doctests) ---

  @doc """
  Loads the current tallies (option_id => count) for the session's current question.

  Returns an empty map when there is no current_question or no results yet.
  """
  def current_tallies(%Session{current_question: %Question{} = q} = session) do
    results =
      Result
      |> where([r], r.session_id == ^session.id)
      |> where([r], r.question_id == ^q.id)
      |> Repo.all()

    tallies(results, q)
  end

  def current_tallies(_), do: %{}

  @doc """
  Loads per-option voter info for the current question (for showing identicons of who voted what).
  Returns %{option_id => [%{seed: string, label: string}, ...]}
  MC always sees this; non-MC only when the session.show_voter_choices is true (and results visible).
  """
  def current_voter_choices(%Session{current_question: %Question{} = q} = session) do
    results =
      Result
      |> where([r], r.session_id == ^session.id)
      |> where([r], r.question_id == ^q.id)
      |> Repo.all()

    results
    |> Enum.group_by(& &1.option_id)
    |> Map.new(fn {opt_id, rs} ->
      voters =
        Enum.map(rs, fn r ->
          seed =
            cond do
              r.user_id -> r.user_id
              r.visitor_id -> r.visitor_id
              true -> "unknown"
            end

          %{seed: seed, label: "Voter"}
        end)

      {opt_id, voters}
    end)
  end

  def current_voter_choices(_), do: %{}

  @doc """
  Returns the option_id that the given identity has currently selected for the
  session's current question, or nil if none.

  Used to restore @my_vote_id on reconnect or after code entry for returning voters.
  """
  def current_vote_for_identity(%Session{current_question: %Question{} = q} = session, identity)
      when is_map(identity) do
    voter_dynamic = voter_dynamic(identity)

    Result
    |> where([r], r.session_id == ^session.id)
    |> where([r], r.question_id == ^q.id)
    |> where(^voter_dynamic)
    |> select([r], r.option_id)
    |> Repo.one()
  end

  def current_vote_for_identity(_session, _identity), do: nil

  @doc """
  Removes the current vote (if any) for the given identity on the session's
  current question. Only allowed while voting is open.
  Broadcasts so all clients (including MC) see the updated counts.
  """
  def remove_vote(%Session{} = session, identity) when is_map(identity) do
    cond do
      not voting_open?(session) ->
        {:error, :voting_closed}

      is_nil(session.current_question_id) ->
        {:error, :no_current_question}

      true ->
        voter_dynamic = voter_dynamic(identity)

        {deleted, _} =
          Result
          |> where([r], r.session_id == ^session.id)
          |> where([r], r.question_id == ^session.current_question_id)
          |> where(^voter_dynamic)
          |> Repo.delete_all()

        if deleted > 0 do
          broadcast_to_session(
            session.slug,
            {:vote_cast, session.id, session.current_question_id}
          )
        end

        {:ok, :removed}
    end
  end

  @doc """
  Pure function: given results for a question and the question struct (with
  preloaded options), returns %{option_id => vote_count}.

  ## Examples

      iex> alias Slidex.Voting.Result
      iex> alias Slidex.Polling.Option
      iex> o1 = %Option{id: "opt-1"}
      iex> o2 = %Option{id: "opt-2"}
      iex> results = [%Result{option_id: "opt-1"}, %Result{option_id: "opt-1"}, %Result{option_id: "opt-2"}]
      iex> Slidex.Voting.tallies(results, %{options: [o1, o2]})
      %{"opt-1" => 2, "opt-2" => 1}
  """
  def tallies(results, %{options: options}) when is_list(results) and is_list(options) do
    counts = Enum.frequencies_by(results, & &1.option_id)

    Map.new(options, fn opt -> {opt.id, Map.get(counts, opt.id, 0)} end)
  end

  def tallies(_results, _question), do: %{}

  @doc "Total number of votes (Results) cast across all sessions."
  def total_votes_cast do
    Result |> Repo.aggregate(:count, :id)
  end

  @doc """
  Returns true if any option anywhere in the poll (or the provided questions)
  has is_correct set. Used to decide whether to offer a leaderboard UI.
  """
  def has_correct_answers?(%Poll{questions: questions}) when is_list(questions) do
    Enum.any?(questions, fn
      %{options: opts} when is_list(opts) -> Enum.any?(opts, & &1.is_correct)
      _ -> false
    end)
  end

  def has_correct_answers?(_), do: false

  @doc """
  Pure computation of a correctness leaderboard.

  Takes the list of all Results for the session and the list of Questions
  (each with their options). For each unique voter (user or visitor) counts
  how many of the questions they voted on had their chosen option marked
  is_correct.

  Returns a list of maps sorted by correct count desc, stable tie-break by key.
  Each map has keys: :key (for identicon seed), :kind (:user or :visitor),
  :correct (integer), :voted (integer).

  This is intentionally pure so it is trivial to unit test with doctests.
  """
  def leaderboard(results, questions) when is_list(results) and is_list(questions) do
    # Build a map question_id => set of correct option_ids
    correct_by_question =
      Map.new(questions, fn q ->
        correct_ids =
          q.options
          |> Enum.filter(& &1.is_correct)
          |> Enum.map(& &1.id)
          |> MapSet.new()

        {q.id, correct_ids}
      end)

    results
    |> Enum.group_by(&voter_key/1)
    |> Enum.map(fn {key, voter_results} ->
      correct =
        voter_results
        |> Enum.count(fn r ->
          correct_set = Map.get(correct_by_question, r.question_id, MapSet.new())
          MapSet.member?(correct_set, r.option_id)
        end)

      voted = length(voter_results)

      %{key: key, kind: voter_kind(key), correct: correct, voted: voted}
    end)
    |> Enum.sort_by(fn m -> {-m.correct, m.key} end)
  end

  def leaderboard(_results, _questions), do: []

  defp voter_key(%Result{user_id: uid}) when is_binary(uid), do: "user:#{uid}"
  defp voter_key(%Result{visitor_id: vid}) when is_binary(vid), do: "visitor:#{vid}"
  defp voter_key(_), do: "unknown"

  defp voter_kind("user:" <> _), do: :user
  defp voter_kind("visitor:" <> _), do: :visitor
  defp voter_kind(_), do: :unknown
end
