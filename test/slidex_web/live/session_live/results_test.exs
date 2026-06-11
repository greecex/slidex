defmodule SlidexWeb.SessionLive.ResultsTest do
  use SlidexWeb.ConnCase

  import Phoenix.LiveViewTest
  import Slidex.CampaignsFixtures
  import Slidex.PollingFixtures
  import Slidex.VotingFixtures

  alias Slidex.Voting

  setup :register_and_log_in_user

  setup %{scope: scope} do
    poll = poll_fixture(scope)
    question = question_fixture(scope, poll)
    option = option_fixture(scope, question)
    session = session_fixture(scope, poll, %{state: :active})
    %{session: session, question: question, option: option}
  end

  test "shows each question's tally", %{
    conn: conn,
    session: session,
    question: question,
    option: option
  } do
    {:ok, participant} = Voting.find_or_create_participant(session, "voter-1")
    {:ok, _} = Voting.cast_vote(session, participant, question, option)

    {:ok, lv, _html} = live(conn, ~p"/sessions/#{session}/results")

    assert has_element?(lv, "#result-#{question.id}", "100%")
  end

  test "updates live as votes arrive", %{
    conn: conn,
    session: session,
    question: question,
    option: option
  } do
    {:ok, lv, _html} = live(conn, ~p"/sessions/#{session}/results")
    refute has_element?(lv, "#result-#{question.id}", "100%")

    {:ok, participant} = Voting.find_or_create_participant(session, "voter-1")
    {:ok, _} = Voting.cast_vote(session, participant, question, option)

    assert has_element?(lv, "#result-#{question.id}", "100%")
  end
end
