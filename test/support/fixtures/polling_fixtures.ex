defmodule Slidex.PollingFixtures do
  @moduledoc """
  Test helpers that build `Slidex.Polling` entities (questions and options).
  """

  alias Slidex.Polling

  @doc """
  Generate a question.
  """
  def question_fixture(scope, poll, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{body: "some question body"})

    {:ok, question} = Polling.create_question(scope, poll, attrs)
    question
  end

  @doc """
  Generate an option.
  """
  def option_fixture(scope, question, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{body: "some option body"})

    {:ok, option} = Polling.create_option(scope, question, attrs)
    option
  end
end
