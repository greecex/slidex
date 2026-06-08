defmodule Slidex.Authorization do
  @moduledoc """
  User-scoped authorization for Poll, Question, Option, Session
  """

  alias Slidex.{Accounts, Repo, Campaigns, Polling, Voting}

  def authorize(%Accounts.Scope{} = scope, %Campaigns.Poll{} = poll),
    do: ok_or_forbidden(poll.user_id == scope.user.id)

  def authorize(%Accounts.Scope{} = scope, %Polling.Question{} = question) do
    question = Repo.preload(question, :poll)
    authorize(scope, question.poll)
  end

  def authorize(%Accounts.Scope{} = scope, %Polling.Option{} = option) do
    option = Repo.preload(option, question: :poll)
    authorize(scope, option.question.poll)
  end

  def authorize(%Accounts.Scope{} = scope, %Voting.Session{} = voting_session) do
    voting_session = Repo.preload(voting_session, :poll)
    authorize(scope, voting_session.poll)
  end

  defp ok_or_forbidden(true), do: :ok
  defp ok_or_forbidden(false), do: {:error, :forbidden}
end
