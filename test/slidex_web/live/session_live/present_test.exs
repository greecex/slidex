defmodule SlidexWeb.SessionLive.PresentTest do
  use SlidexWeb.ConnCase

  import Phoenix.LiveViewTest
  import Slidex.CampaignsFixtures
  import Slidex.PollingFixtures
  import Slidex.VotingFixtures

  alias Slidex.Voting

  setup :register_and_log_in_user

  setup %{scope: scope} do
    poll = poll_fixture(scope)
    first = question_fixture(scope, poll)
    second = question_fixture(scope, poll)
    option = option_fixture(scope, first)

    session = session_fixture(scope, poll, %{state: :pending})
    %{session: session, first: first, second: second, option: option}
  end

  test "starts the session and shows the first question", %{
    conn: conn,
    session: session,
    first: first
  } do
    {:ok, lv, html} = live(conn, ~p"/sessions/#{session}/present")

    assert html =~ session.title
    assert has_element?(lv, "#start-session")

    lv |> element("#start-session") |> render_click()

    assert has_element?(lv, "#current-question")
    assert render(lv) =~ first.body
    assert has_element?(lv, "#next-question")
  end

  test "shows a presence count", %{conn: conn, session: session} do
    {:ok, lv, _html} = live(conn, ~p"/sessions/#{session}/present")

    assert has_element?(lv, "#presence-count")
  end

  test "shows the join QR code and link", %{conn: conn, session: session} do
    {:ok, lv, _html} = live(conn, ~p"/sessions/#{session}/present")

    assert has_element?(lv, "#join-qr svg")
    assert has_element?(lv, "#session-share a", session.slug)
  end

  test "collapses and expands the join panel", %{conn: conn, session: session} do
    {:ok, lv, _html} = live(conn, ~p"/sessions/#{session}/present")
    assert has_element?(lv, "#join-qr")

    lv |> element("#toggle-share") |> render_click()
    refute has_element?(lv, "#join-qr")

    lv |> element("#toggle-share") |> render_click()
    assert has_element?(lv, "#join-qr")
  end

  test "advances to the next question", %{conn: conn, session: session, second: second} do
    {:ok, lv, _html} = live(conn, ~p"/sessions/#{session}/present")

    lv |> element("#start-session") |> render_click()
    lv |> element("#next-question") |> render_click()

    assert render(lv) =~ second.body
  end

  test "ends the session but keeps the final results visible", %{conn: conn, session: session} do
    {:ok, lv, _html} = live(conn, ~p"/sessions/#{session}/present")

    lv |> element("#start-session") |> render_click()
    lv |> element("#end-session") |> render_click()

    assert render(lv) =~ "ended"
    assert has_element?(lv, "#current-question")
    refute has_element?(lv, "#end-session")
  end

  test "shows live results as votes come in", %{
    conn: conn,
    scope: scope,
    session: session,
    first: first,
    option: option
  } do
    {:ok, lv, _html} = live(conn, ~p"/sessions/#{session}/present")
    lv |> element("#start-session") |> render_click()

    started = Voting.get_session!(scope, session.id)
    {:ok, participant} = Voting.find_or_create_participant(started, "voter-1")
    {:ok, _vote} = Voting.cast_vote(started, participant, first, option)

    assert render(lv) =~ "100%"
  end
end
