defmodule SlidexWeb.PollLiveTest do
  use SlidexWeb.ConnCase

  import Phoenix.LiveViewTest
  import Slidex.CampaignsFixtures

  @create_attrs %{
    title: "some title",
    is_public: true,
    access_code: "some access_code",
    expires_at: "2026-06-05T14:14:00Z",
    closed_at: "2026-06-05T14:14:00Z",
    archived_at: "2026-06-05T14:14:00.000000Z"
  }
  @update_attrs %{
    title: "some updated title",
    is_public: false,
    access_code: "some updated access_code",
    expires_at: "2026-06-06T14:14:00Z",
    closed_at: "2026-06-06T14:14:00Z",
    archived_at: "2026-06-06T14:14:00.000000Z"
  }
  @invalid_attrs %{
    title: nil,
    is_public: false,
    access_code: nil,
    expires_at: nil,
    closed_at: nil,
    archived_at: nil
  }

  setup :register_and_log_in_user

  defp create_poll(%{scope: scope}) do
    poll = poll_fixture(scope)

    %{poll: poll}
  end

  describe "Index" do
    setup [:create_poll]

    test "lists all polls", %{conn: conn, poll: poll} do
      {:ok, _index_live, html} = live(conn, ~p"/polls")

      assert html =~ "Listing Polls"
      assert html =~ poll.title
    end

    test "saves new poll", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/polls")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Poll")
               |> render_click()
               |> follow_redirect(conn, ~p"/polls/new")

      assert render(form_live) =~ "New Poll"

      assert form_live
             |> form("#poll-form", poll: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#poll-form", poll: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/polls")

      html = render(index_live)
      assert html =~ "Poll created successfully"
      assert html =~ "some title"
    end

    test "updates poll in listing", %{conn: conn, poll: poll} do
      {:ok, index_live, _html} = live(conn, ~p"/polls")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#polls-#{poll.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/polls/#{poll}/edit")

      assert render(form_live) =~ "Edit Poll"

      assert form_live
             |> form("#poll-form", poll: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#poll-form", poll: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/polls")

      html = render(index_live)
      assert html =~ "Poll updated successfully"
      assert html =~ "some updated title"
    end

    test "deletes poll in listing", %{conn: conn, poll: poll} do
      {:ok, index_live, _html} = live(conn, ~p"/polls")

      assert index_live |> element("#polls-#{poll.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#polls-#{poll.id}")
    end
  end

  describe "Show" do
    setup [:create_poll]

    test "displays poll", %{conn: conn, poll: poll} do
      {:ok, _show_live, html} = live(conn, ~p"/polls/#{poll}")

      assert html =~ "Show Poll"
      assert html =~ poll.title
    end

    test "updates poll and returns to show", %{conn: conn, poll: poll} do
      {:ok, show_live, _html} = live(conn, ~p"/polls/#{poll}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/polls/#{poll}/edit?return_to=show")

      assert render(form_live) =~ "Edit Poll"

      assert form_live
             |> form("#poll-form", poll: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#poll-form", poll: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/polls/#{poll}")

      html = render(show_live)
      assert html =~ "Poll updated successfully"
      assert html =~ "some updated title"
    end
  end
end
