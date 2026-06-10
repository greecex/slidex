defmodule Slidex.VotingTest do
  use Slidex.DataCase

  alias Slidex.Voting
  alias Slidex.Voting.{Participant, Vote}

  import Slidex.AccountsFixtures, only: [user_scope_fixture: 0]
  import Slidex.CampaignsFixtures
  import Slidex.PollingFixtures
  import Slidex.VotingFixtures

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
end
