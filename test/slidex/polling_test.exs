defmodule Slidex.PollingTest do
  use Slidex.DataCase, async: true

  alias Slidex.Polling
  alias Slidex.Polling.{Option, Question}

  import Slidex.AccountsFixtures, only: [user_scope_fixture: 0]
  import Slidex.CampaignsFixtures
  import Slidex.PollingFixtures

  describe "questions" do
    test "create_question/3 with valid data creates a question at position 0" do
      scope = user_scope_fixture()
      poll = poll_fixture(scope)

      assert {:ok, %Question{} = question} =
               Polling.create_question(scope, poll, %{body: "What is your favorite color?"})

      assert question.body == "What is your favorite color?"
      assert question.poll_id == poll.id
      assert question.position == 0
    end

    test "create_question/3 assigns an incrementing position within the poll" do
      scope = user_scope_fixture()
      poll = poll_fixture(scope)

      first = question_fixture(scope, poll)
      second = question_fixture(scope, poll)
      third = question_fixture(scope, poll)

      assert [first.position, second.position, third.position] == [0, 1, 2]
    end

    test "create_question/3 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      poll = poll_fixture(scope)

      assert {:error, %Ecto.Changeset{}} = Polling.create_question(scope, poll, %{body: nil})
    end

    test "create_question/3 with an unauthorized scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      poll = poll_fixture(scope)

      assert_raise MatchError, fn ->
        Polling.create_question(other_scope, poll, %{body: "nope"})
      end
    end
  end

  describe "options" do
    test "create_option/3 with valid data creates an option at position 0" do
      scope = user_scope_fixture()
      poll = poll_fixture(scope)
      question = question_fixture(scope, poll)

      assert {:ok, %Option{} = option} =
               Polling.create_option(scope, question, %{body: "Blue", is_correct: true})

      assert option.body == "Blue"
      assert option.question_id == question.id
      assert option.is_correct == true
      assert option.position == 0
    end

    test "create_option/3 assigns an incrementing position within the question" do
      scope = user_scope_fixture()
      poll = poll_fixture(scope)
      question = question_fixture(scope, poll)

      first = option_fixture(scope, question)
      second = option_fixture(scope, question)
      third = option_fixture(scope, question)

      assert [first.position, second.position, third.position] == [0, 1, 2]
    end

    test "create_option/3 positions are scoped per question" do
      scope = user_scope_fixture()
      poll = poll_fixture(scope)
      first_question = question_fixture(scope, poll)
      second_question = question_fixture(scope, poll)

      _ = option_fixture(scope, first_question)
      _ = option_fixture(scope, first_question)
      option = option_fixture(scope, second_question)

      assert option.position == 0
    end
  end
end
