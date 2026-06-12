defmodule SlidexWeb.SessionLive.JoinTest do
  use SlidexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Slidex.AccountsFixtures, only: [user_scope_fixture: 0]
  import Slidex.CampaignsFixtures
  import Slidex.PollingFixtures
  import Slidex.VotingFixtures

  alias Slidex.Voting

  defp active_session(opts \\ []) do
    scope = user_scope_fixture()
    poll = poll_fixture(scope)
    question = question_fixture(scope, poll)
    a = option_fixture(scope, question)
    b = option_fixture(scope, question)

    session = session_fixture(scope, poll, Enum.into(opts, %{state: :active, is_public: true}))
    {:ok, session} = Voting.set_current_question(scope, session, question)

    %{scope: scope, session: session, question: question, a: a, b: b}
  end

  test "a guest can join a public session and vote", %{conn: conn} do
    %{session: session, question: question, a: a} = active_session()

    {:ok, lv, html} = live(conn, ~p"/join/#{session.slug}")
    assert html =~ session.title
    assert html =~ question.body

    lv |> element("#option-#{a.id}") |> render_click()

    assert has_element?(lv, "#option-#{a.id}.btn-primary")
  end

  test "shows a presence count", %{conn: conn} do
    %{session: session} = active_session()

    {:ok, lv, _html} = live(conn, ~p"/join/#{session.slug}")

    assert has_element?(lv, "#presence-count")
  end

  test "a non-public session requires login", %{conn: conn} do
    %{session: session} = active_session(is_public: false)

    assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/join/#{session.slug}")
    assert path == ~p"/users/log-in"
  end

  test "an ended session shows that it has ended", %{conn: conn} do
    %{scope: scope, session: session} = active_session()
    {:ok, ended} = Voting.close_session(scope, session)

    {:ok, _lv, html} = live(conn, ~p"/join/#{ended.slug}")
    assert html =~ "ended"
  end

  test "shows final results after the session ends", %{conn: conn} do
    %{scope: scope, session: session, question: question, a: a} = active_session()
    {:ok, participant} = Voting.find_or_create_participant(session, "voter-x")
    {:ok, _} = Voting.cast_vote(session, participant, question, a)
    {:ok, ended} = Voting.close_session(scope, session)

    {:ok, lv, _html} = live(conn, ~p"/join/#{ended.slug}")

    assert has_element?(lv, "#result-#{question.id}", "100%")
  end

  test "highlights the participant's own vote when the session ends live", %{conn: conn} do
    %{scope: scope, session: session, question: question, a: a} = active_session()

    {:ok, lv, _html} = live(conn, ~p"/join/#{session.slug}")
    lv |> element("#option-#{a.id}") |> render_click()

    {:ok, _ended} = Voting.close_session(scope, session)

    assert has_element?(lv, "#result-#{question.id}", "Your vote")
  end

  test "a pending session shows a waiting message", %{conn: conn} do
    scope = user_scope_fixture()
    poll = poll_fixture(scope)
    session = session_fixture(scope, poll, %{state: :pending, is_public: true})

    {:ok, _lv, html} = live(conn, ~p"/join/#{session.slug}")
    assert html =~ "Waiting for the host"
  end
end
