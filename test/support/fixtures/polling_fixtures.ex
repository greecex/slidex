defmodule Slidex.PollingFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Slidex.Polling` context.
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
