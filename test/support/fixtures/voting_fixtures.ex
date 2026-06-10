defmodule Slidex.VotingFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Slidex.Voting` context.
  """

  alias Slidex.Voting
  alias Slidex.Voting.Participant

  @doc """
  Generate a session for the given scope and poll.
  """
  def session_fixture(scope, poll, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{title: "some session"})

    {:ok, session} = Voting.create_session(scope, poll, attrs)
    session
  end

  @doc """
  Generate a participant for the given session.
  """
  def participant_fixture(session, attrs \\ %{}) do
    token = Map.get(attrs, :token, "tok-#{System.unique_integer([:positive])}")

    {:ok, participant} = Voting.find_or_create_participant(session, token, attrs)
    participant
  end

  @doc """
  Generate a vote from the given participant for the given option.
  """
  def vote_fixture(session, %Participant{} = participant, question, option) do
    {:ok, vote} = Voting.cast_vote(session, participant, question, option)
    vote
  end
end
