defmodule Slidex.Polling do
  @moduledoc """
  The Polling context.
  """

  import Ecto.Query
  import Slidex.Preloader
  import Slidex.Authorization
  alias Slidex.Repo

  alias Slidex.Accounts.Scope
  alias Slidex.Campaigns.Poll
  alias __MODULE__.{Question, Option, Reorder}

  # Questions

  def list_questions(%Scope{} = scope, %Poll{} = poll) do
    :ok = authorize(scope, poll)

    Question
    |> where([q], q.poll_id == ^poll.id)
    |> order_by([q], asc: q.position, asc: q.inserted_at)
    |> Repo.all()
  end

  def get_question!(%Scope{} = scope, id) do
    Question
    |> join(:inner, [q], p in assoc(q, :poll))
    |> where([q, p], p.user_id == ^scope.user.id)
    |> Repo.get!(id)
  end

  def create_question(%Scope{} = scope, %Poll{} = poll, attrs) do
    :ok = authorize(scope, poll)

    %Question{poll_id: poll.id}
    |> Question.changeset(attrs)
    |> Repo.insert()
    |> with_preloads()
  end

  # TODO: Add check to prevent editing if the question already has responses
  def update_question(%Scope{} = scope, %Question{} = question, attrs) do
    :ok = authorize(scope, question)

    question
    |> Question.changeset(attrs)
    |> Repo.update()
    |> with_preloads()
  end

  # TODO: Add check to prevent deletion if the question already has responses
  def delete_question(%Scope{} = scope, %Question{} = question) do
    :ok = authorize(scope, question)

    Repo.delete(question)
  end

  # Options

  def list_options(%Scope{} = scope, %Question{} = question) do
    :ok = authorize(scope, question)

    Option
    |> where([o], o.question_id == ^question.id)
    |> order_by([o], asc: o.position, asc: o.inserted_at)
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
    :ok = authorize(scope, question)

    %Option{question_id: question.id}
    |> Option.changeset(attrs)
    |> Repo.insert()
    |> with_preloads()
  end

  # TODO: Add check to prevent editing if the question already has responses
  def update_option(%Scope{} = scope, %Option{} = option, attrs) do
    :ok = authorize(scope, option)

    option
    |> Option.changeset(attrs)
    |> Repo.update()
    |> with_preloads()
  end

  # TODO: Add check to prevent deletion if the question already has responses
  def delete_option(%Scope{} = scope, %Option{} = option) do
    :ok = authorize(scope, option)

    Repo.delete(option)
  end

  defdelegate reorder(scope, question_or_option, direction),
    to: Reorder,
    as: :move
end
