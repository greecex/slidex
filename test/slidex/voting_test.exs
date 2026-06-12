defmodule Slidex.VotingTest do
  use Slidex.DataCase, async: true

  alias Slidex.Voting
  alias Slidex.Voting.{Participant, Vote}

  import Slidex.AccountsFixtures, only: [user_scope_fixture: 0]
  import Slidex.CampaignsFixtures
  import Slidex.PollingFixtures
  import Slidex.VotingFixtures

  doctest Slidex.Voting, only: [session_topic: 1]
  doctest Slidex.Voting.Session, only: [status_label: 1]
  doctest Slidex.Voting.Tally

  describe "find_or_create_participant/3" do
    setup do
      scope = user_scope_fixture()
      poll = poll_fixture(scope)
      %{scope: scope, session: session_fixture(scope, poll)}
    end

    test "creates a participant for a new token", %{session: session} do
      assert {:ok, %Participant{} = participant} =
               Voting.find_or_create_participant(session, "tok-1", %{display_name: "Ada"})

      assert participant.session_id == session.id
      assert participant.token == "tok-1"
      assert participant.display_name == "Ada"
      assert is_nil(participant.user_id)
    end

    test "returns the existing participant for the same token", %{session: session} do
      {:ok, first} = Voting.find_or_create_participant(session, "tok-1")
      {:ok, second} = Voting.find_or_create_participant(session, "tok-1")

      assert first.id == second.id
    end

    test "associates the user when provided", %{scope: scope, session: session} do
      {:ok, participant} =
        Voting.find_or_create_participant(session, "tok-1", %{user_id: scope.user.id})

      assert participant.user_id == scope.user.id
    end
  end

  describe "cast_vote/4" do
    setup do
      scope = user_scope_fixture()
      poll = poll_fixture(scope)
      session = session_fixture(scope, poll, %{state: :active})
      question = question_fixture(scope, poll)
      option = option_fixture(scope, question)
      participant = participant_fixture(session)

      %{
        scope: scope,
        poll: poll,
        session: session,
        question: question,
        option: option,
        participant: participant
      }
    end

    test "records a vote", %{session: session, participant: p, question: q, option: o} do
      assert {:ok, %Vote{} = vote} = Voting.cast_vote(session, p, q, o)
      assert vote.option_id == o.id
      assert Voting.tally(session, q) == %{o.id => 1}
    end

    test "re-voting updates the chosen option without adding a second vote", %{
      scope: scope,
      session: session,
      participant: p,
      question: q,
      option: o
    } do
      other = option_fixture(scope, q)

      {:ok, _} = Voting.cast_vote(session, p, q, o)
      {:ok, _} = Voting.cast_vote(session, p, q, other)

      assert Voting.tally(session, q) == %{other.id => 1}
    end

    test "rejects an option that does not belong to the question", %{
      scope: scope,
      session: session,
      participant: p,
      question: q
    } do
      other_question = question_fixture(scope, session.poll)
      stray_option = option_fixture(scope, other_question)

      assert {:error, :option_not_in_question} = Voting.cast_vote(session, p, q, stray_option)
    end

    test "rejects a question that does not belong to the session's poll", %{
      session: session,
      participant: p,
      option: o
    } do
      other_scope = user_scope_fixture()
      other_poll = poll_fixture(other_scope)
      other_question = question_fixture(other_scope, other_poll)

      assert {:error, :question_not_in_session} = Voting.cast_vote(session, p, other_question, o)
    end

    test "rejects voting on a pending session", %{
      scope: scope,
      poll: poll,
      question: q,
      option: o
    } do
      pending = session_fixture(scope, poll, %{state: :pending})
      p = participant_fixture(pending)

      assert {:error, :session_not_votable} = Voting.cast_vote(pending, p, q, o)
    end

    test "allows voting on a survey", %{scope: scope, poll: poll, question: q, option: o} do
      survey = session_fixture(scope, poll, %{state: :survey})
      p = participant_fixture(survey)

      assert {:ok, %Vote{}} = Voting.cast_vote(survey, p, q, o)
    end

    test "rejects voting on a closed survey", %{scope: scope, poll: poll, question: q, option: o} do
      survey = session_fixture(scope, poll, %{state: :survey})
      {:ok, closed} = Voting.close_session(scope, survey)
      p = participant_fixture(closed)

      assert {:error, :session_not_votable} = Voting.cast_vote(closed, p, q, o)
    end
  end

  describe "tally/2" do
    test "counts votes per option" do
      scope = user_scope_fixture()
      poll = poll_fixture(scope)
      session = session_fixture(scope, poll, %{state: :active})
      question = question_fixture(scope, poll)
      yes = option_fixture(scope, question)
      no = option_fixture(scope, question)

      vote_fixture(session, participant_fixture(session), question, yes)
      vote_fixture(session, participant_fixture(session), question, yes)
      vote_fixture(session, participant_fixture(session), question, no)

      assert Voting.tally(session, question) == %{yes.id => 2, no.id => 1}
    end
  end

  describe "tally_by_question/1" do
    test "groups option counts by question" do
      scope = user_scope_fixture()
      poll = poll_fixture(scope)
      session = session_fixture(scope, poll, %{state: :active})
      q1 = question_fixture(scope, poll)
      a = option_fixture(scope, q1)
      b = option_fixture(scope, q1)
      q2 = question_fixture(scope, poll)
      c = option_fixture(scope, q2)

      vote_fixture(session, participant_fixture(session), q1, a)
      vote_fixture(session, participant_fixture(session), q1, a)
      vote_fixture(session, participant_fixture(session), q1, b)
      vote_fixture(session, participant_fixture(session), q2, c)

      assert Voting.tally_by_question(session) == %{
               q1.id => %{a.id => 2, b.id => 1},
               q2.id => %{c.id => 1}
             }
    end
  end

  describe "session lifecycle" do
    setup do
      scope = user_scope_fixture()
      %{scope: scope, poll: poll_fixture(scope)}
    end

    test "start_session moves a pending session to active", %{scope: scope, poll: poll} do
      session = session_fixture(scope, poll, %{state: :pending})

      assert {:ok, started} = Voting.start_session(scope, session)
      assert started.state == :active
      # the slug stays stable across the update
      assert started.slug == session.slug
    end

    test "start_session rejects a session that is not pending", %{scope: scope, poll: poll} do
      session = session_fixture(scope, poll, %{state: :active})
      assert {:error, :invalid_transition} = Voting.start_session(scope, session)
    end

    test "closing a voting session ends it", %{scope: scope, poll: poll} do
      session = session_fixture(scope, poll, %{state: :active})

      assert {:ok, closed} = Voting.close_session(scope, session)
      assert closed.state == :ended
      assert closed.closed_at
    end

    test "closing a survey keeps its survey state", %{scope: scope, poll: poll} do
      survey = session_fixture(scope, poll, %{state: :survey})

      assert {:ok, closed} = Voting.close_session(scope, survey)
      assert closed.state == :survey
      assert closed.closed_at
    end

    test "reopening a voting session makes it active again", %{scope: scope, poll: poll} do
      session = session_fixture(scope, poll, %{state: :active})
      {:ok, closed} = Voting.close_session(scope, session)

      assert {:ok, reopened} = Voting.reopen_session(scope, closed)
      assert reopened.state == :active
      assert is_nil(reopened.closed_at)
    end

    test "set_current_question points the session at a question", %{scope: scope, poll: poll} do
      session = session_fixture(scope, poll, %{state: :active})
      question = question_fixture(scope, poll)

      assert {:ok, updated} = Voting.set_current_question(scope, session, question)
      assert updated.current_question_id == question.id
    end

    test "set_current_question rejects a question from another poll", %{scope: scope, poll: poll} do
      session = session_fixture(scope, poll, %{state: :active})
      other_scope = user_scope_fixture()
      stray = question_fixture(other_scope, poll_fixture(other_scope))

      assert {:error, :question_not_in_session} =
               Voting.set_current_question(scope, session, stray)
    end

    test "lifecycle actions require the owner", %{scope: scope, poll: poll} do
      session = session_fixture(scope, poll, %{state: :pending})
      other_scope = user_scope_fixture()

      assert_raise MatchError, fn -> Voting.start_session(other_scope, session) end
    end
  end

  describe "public lookups" do
    setup do
      scope = user_scope_fixture()
      %{scope: scope, poll: poll_fixture(scope)}
    end

    test "get_session_by_slug returns the session with its poll", %{scope: scope, poll: poll} do
      session = session_fixture(scope, poll)

      found = Voting.get_session_by_slug(session.slug)
      assert found.id == session.id
      assert found.poll.id == poll.id
    end

    test "get_session_by_slug returns nil for an unknown slug" do
      assert Voting.get_session_by_slug("does-not-exist") == nil
    end

    test "list_session_questions returns ordered questions with options", %{
      scope: scope,
      poll: poll
    } do
      session = session_fixture(scope, poll, %{state: :survey})
      first = question_fixture(scope, poll)
      _ = option_fixture(scope, first)
      second = question_fixture(scope, poll)

      questions = Voting.list_session_questions(session)
      assert Enum.map(questions, & &1.id) == [first.id, second.id]
      assert [_option | _] = hd(questions).options
    end

    test "list_participant_votes maps each question to the chosen option", %{
      scope: scope,
      poll: poll
    } do
      session = session_fixture(scope, poll, %{state: :active})
      question = question_fixture(scope, poll)
      option = option_fixture(scope, question)
      participant = participant_fixture(session)
      {:ok, _} = Voting.cast_vote(session, participant, question, option)

      assert Voting.list_participant_votes(session, participant) == %{question.id => option.id}
    end
  end
end
