defmodule Slidex.Authorization do
  @moduledoc """
  User-scoped authorization for Poll, Question, Option
  """

  alias Slidex.{Accounts, Repo, Campaigns, Polling}

  def authorize(%Accounts.Scope{} = scope, %Campaigns.Poll{} = poll),
    do: ok_or_forbidden(poll.user_id == scope.user.id)

  def authorize(%Accounts.Scope{} = scope, %Polling.Question{} = question) do
    question = Repo.preload(question, :poll)
    ok_or_forbidden(question.poll.user_id == scope.user.id)
  end

  def authorize(%Accounts.Scope{} = scope, %Polling.Option{} = option) do
    option = Repo.preload(option, question: :poll)
    ok_or_forbidden(option.question.poll.user_id == scope.user.id)
  end

  defp ok_or_forbidden(true), do: :ok
  defp ok_or_forbidden(false), do: {:error, :forbidden}
end
