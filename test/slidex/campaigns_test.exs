defmodule Slidex.CampaignsTest do
  use Slidex.DataCase, async: true

  alias Slidex.Campaigns

  describe "polls" do
    alias Slidex.Campaigns.Poll

    import Slidex.AccountsFixtures, only: [user_scope_fixture: 0]
    import Slidex.CampaignsFixtures

    @invalid_attrs %{title: nil}

    test "list_polls/1 returns all scoped polls" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      poll = poll_fixture(scope)
      other_poll = poll_fixture(other_scope)
      assert Campaigns.list_polls(scope) == [poll]
      assert Campaigns.list_polls(other_scope) == [other_poll]
    end

    test "count_polls/0 counts polls across all users" do
      assert Campaigns.count_polls() == 0

      poll_fixture(user_scope_fixture())
      poll_fixture(user_scope_fixture())

      assert Campaigns.count_polls() == 2
    end

    test "get_poll!/2 returns the poll with given id" do
      scope = user_scope_fixture()
      poll = poll_fixture(scope)
      other_scope = user_scope_fixture()
      assert Campaigns.get_poll!(scope, poll.id).id == poll.id
      assert_raise Ecto.NoResultsError, fn -> Campaigns.get_poll!(other_scope, poll.id) end
    end

    test "create_poll/2 with valid data creates a poll" do
      valid_attrs = %{title: "some title", access_code: "some access_code"}

      scope = user_scope_fixture()

      assert {:ok, %Poll{} = poll} = Campaigns.create_poll(scope, valid_attrs)
      assert poll.title == "some title"
      assert poll.access_code == "some access_code"
      assert poll.user_id == scope.user.id
    end

    test "create_poll/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Campaigns.create_poll(scope, @invalid_attrs)
    end

    test "update_poll/3 with valid data updates the poll" do
      scope = user_scope_fixture()
      poll = poll_fixture(scope)

      update_attrs = %{title: "some updated title", access_code: "some updated access_code"}

      assert {:ok, %Poll{} = poll} = Campaigns.update_poll(scope, poll, update_attrs)
      assert poll.title == "some updated title"
      assert poll.access_code == "some updated access_code"
    end

    test "update_poll/3 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      poll = poll_fixture(scope)

      assert_raise MatchError, fn ->
        Campaigns.update_poll(other_scope, poll, %{})
      end
    end

    test "update_poll/3 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      poll = poll_fixture(scope)
      assert {:error, %Ecto.Changeset{}} = Campaigns.update_poll(scope, poll, @invalid_attrs)
      assert poll.title == Campaigns.get_poll!(scope, poll.id).title
    end

    test "delete_poll/2 deletes the poll" do
      scope = user_scope_fixture()
      poll = poll_fixture(scope)
      assert {:ok, %Poll{}} = Campaigns.delete_poll(scope, poll)
      assert_raise Ecto.NoResultsError, fn -> Campaigns.get_poll!(scope, poll.id) end
    end

    test "delete_poll/2 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      poll = poll_fixture(scope)
      assert_raise MatchError, fn -> Campaigns.delete_poll(other_scope, poll) end
    end

    test "change_poll/2 returns a poll changeset" do
      scope = user_scope_fixture()
      poll = poll_fixture(scope)
      assert %Ecto.Changeset{} = Campaigns.change_poll(scope, poll)
    end
  end
end
