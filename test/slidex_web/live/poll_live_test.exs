defmodule SlidexWeb.PollLiveTest do
  use SlidexWeb.ConnCase

  import Phoenix.LiveViewTest
  import Slidex.CampaignsFixtures

  setup :register_and_log_in_user

  describe "Index" do
    test "lists the current scope's polls", %{conn: conn, scope: scope} do
      poll = poll_fixture(scope)
      {:ok, index_live, html} = live(conn, ~p"/polls")

      assert html =~ "Polls"
      assert html =~ poll.title
      assert has_element?(index_live, "a", "New Poll")
    end
  end

  describe "Show" do
    test "displays the poll", %{conn: conn, scope: scope} do
      poll = poll_fixture(scope)
      {:ok, _show_live, html} = live(conn, ~p"/polls/#{poll}")

      assert html =~ poll.title
    end
  end

  describe "Form" do
    test "creates a poll and redirects to its questions page", %{conn: conn} do
      {:ok, form_live, _html} = live(conn, ~p"/polls/new")

      assert render(form_live) =~ "New Poll"

      assert form_live
             |> form("#poll-form", poll: %{title: nil})
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, _questions_live, html} =
               form_live
               |> form("#poll-form", poll: %{title: "some title"})
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ "Poll created successfully"
      assert html =~ "some title"
    end

    test "updates a poll and returns to the index", %{conn: conn, scope: scope} do
      poll = poll_fixture(scope)
      {:ok, form_live, _html} = live(conn, ~p"/polls/#{poll}/edit")

      assert render(form_live) =~ "Edit Poll"

      assert {:ok, _index_live, html} =
               form_live
               |> form("#poll-form", poll: %{title: "some updated title"})
               |> render_submit()
               |> follow_redirect(conn, ~p"/polls")

      assert html =~ "Poll updated successfully"
      assert html =~ "some updated title"
    end
  end
end
