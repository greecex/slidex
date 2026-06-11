defmodule SlidexWeb.SessionLive.PresentTest do
  use SlidexWeb.ConnCase

  import Phoenix.LiveViewTest
  import Slidex.CampaignsFixtures
  import Slidex.PollingFixtures
  import Slidex.VotingFixtures

  setup :register_and_log_in_user

  setup %{scope: scope} do
    poll = poll_fixture(scope)
    first = question_fixture(scope, poll)
    second = question_fixture(scope, poll)
    _ = option_fixture(scope, first)

    session = session_fixture(scope, poll, %{state: :pending})
    %{session: session, first: first, second: second}
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

  test "advances to the next question", %{conn: conn, session: session, second: second} do
    {:ok, lv, _html} = live(conn, ~p"/sessions/#{session}/present")

    lv |> element("#start-session") |> render_click()
    lv |> element("#next-question") |> render_click()

    assert render(lv) =~ second.body
  end

  test "ends the session", %{conn: conn, session: session} do
    {:ok, lv, _html} = live(conn, ~p"/sessions/#{session}/present")

    lv |> element("#start-session") |> render_click()
    lv |> element("#end-session") |> render_click()

    assert render(lv) =~ "ended"
  end
end
