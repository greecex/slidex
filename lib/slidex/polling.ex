defmodule Slidex.Polling do
  @moduledoc """
  The Polling context.
  """

  import Ecto.Query, warn: false
  alias Slidex.Repo

  alias Slidex.Accounts.Scope
  alias Slidex.Campaigns.Poll
  alias Slidex.Polling.{Question, Option}

  # Questions

  def list_questions(%Scope{} = scope, %Poll{} = poll) do
    true = poll.user_id == scope.user.id

    Question
    |> where([q], q.poll_id == ^poll.id)
    |> order_by([q], asc: q.position)
    |> Repo.all()
  end

  def get_question!(%Scope{} = scope, id) do
    Question
    |> join(:inner, [q], p in assoc(q, :poll))
    |> where([q, p], p.user_id == ^scope.user.id)
    |> Repo.get!(id)
  end

  def create_question(%Scope{} = scope, %Poll{} = poll, attrs) do
    true = poll.user_id == scope.user.id

    %Question{poll_id: poll.id}
    |> Question.changeset(attrs)
    |> Repo.insert()
  end

  # TODO: Add check to prevent editing if the question already has responses
  def update_question(%Scope{} = scope, %Question{} = question, attrs) do
    question = Repo.preload(question, :poll)
    true = question.poll.user_id == scope.user.id

    question
    |> Question.changeset(attrs)
    |> Repo.update()
  end

  # TODO: Add check to prevent deletion if the question already has responses
  def delete_question(%Scope{} = scope, %Question{} = question) do
    question = Repo.preload(question, :poll)
    true = question.poll.user_id == scope.user.id

    Repo.delete(question)
  end

  # Options

  def list_options(%Scope{} = scope, %Question{} = question) do
    question = Repo.preload(question, :poll)
    true = question.poll.user_id == scope.user.id

    Option
    |> where([o], o.question_id == ^question.id)
    |> order_by([o], asc: o.position)
    |> Repo.all()
  end

  def get_option!(%Scope{} = scope, id) do
    Option
    |> join(:inner, [o], q in assoc(o, :question))
    |> join(:inner, [o, q], p in assoc(q, :poll))
    |> where([o, q, p], p.user_id == ^scope.user.id)
    |> Repo.get!(id)
  end

  def create_option(%Scope{} = scope, %Question{} = question, attrs) do
    question = Repo.preload(question, :poll)
    true = question.poll.user_id == scope.user.id

    %Option{question_id: question.id}
    |> Option.changeset(attrs)
    |> Repo.insert()
  end

  # TODO: Add check to prevent editing if the question already has responses
  def update_option(%Scope{} = scope, %Option{} = option, attrs) do
    option = Repo.preload(option, question: :poll)
    true = option.question.poll.user_id == scope.user.id

    option
    |> Option.changeset(attrs)
    |> Repo.update()
  end

  # TODO: Add check to prevent deletion if the question already has responses
  def delete_option(%Scope{} = scope, %Option{} = option) do
    option = Repo.preload(option, question: :poll)
    true = option.question.poll.user_id == scope.user.id

    Repo.delete(option)
  end
end
