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
    |> with_preloads()
  end

  # TODO: Add check to prevent editing if the question already has responses
  def update_question(%Scope{} = scope, %Question{} = question, attrs) do
    question = Repo.preload(question, :poll)
    true = question.poll.user_id == scope.user.id

    question
    |> Question.changeset(attrs)
    |> Repo.update()
    |> with_preloads()
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
    |> with_preloads()
  end

  # TODO: Add check to prevent editing if the question already has responses
  def update_option(%Scope{} = scope, %Option{} = option, attrs) do
    option = Repo.preload(option, question: :poll)
    true = option.question.poll.user_id == scope.user.id

    option
    |> Option.changeset(attrs)
    |> Repo.update()
    |> with_preloads()
  end

  # TODO: Add check to prevent deletion if the question already has responses
  def delete_option(%Scope{} = scope, %Option{} = option) do
    option = Repo.preload(option, question: :poll)
    true = option.question.poll.user_id == scope.user.id

    Repo.delete(option)
  end

  # Search functionality with optional exclusion

  def search_question_bodies(%Scope{} = scope, search_term, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    excluded = Keyword.get(opts, :excluded, [])

    from(Question, as: :q)
    |> join(:inner, [q], p in assoc(q, :poll), as: :p)
    |> where([p: p], p.user_id == ^scope.user.id)
    |> where([q: q], ilike(q.body, ^"%#{search_term}%"))
    |> maybe_exclude_many(excluded)
    |> order_by([q: q], asc: q.body)
    |> limit(^limit)
    |> distinct([q: q], q.body)
    |> select([q: q], q.body)
    |> Repo.all()
  end

  def search_option_bodies(%Scope{} = scope, search_term, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    excluded = Keyword.get(opts, :excluded, [])

    from(Option, as: :o)
    |> join(:inner, [o: o], q in assoc(o, :question), as: :q)
    |> join(:inner, [q: q], p in assoc(q, :poll), as: :p)
    |> where([p: p], p.user_id == ^scope.user.id)
    |> where([o: o], ilike(o.body, ^"%#{search_term}%"))
    |> maybe_exclude_many(excluded)
    |> order_by([o: o], asc: o.body)
    |> limit(^limit)
    |> distinct([o: o], o.body)
    |> select([o: o], o.body)
    |> Repo.all()
  end

  # Exclusion query helpers for searching across questions and options

  defp maybe_exclude_many(query, list) when is_list(list) do
    Enum.reduce(list, query, fn x, acc -> maybe_exclude_one(acc, x) end)
  end

  defp maybe_exclude_many(query, _), do: query

  defp maybe_exclude_one(query, %Poll{id: poll_id}) do
    query
    |> where([p: p], p.id != ^poll_id)
  end

  defp maybe_exclude_one(query, %Question{id: question_id}) do
    query
    |> where([q: q], q.id != ^question_id)
  end

  defp maybe_exclude_one(query, %Option{id: option_id}) do
    query
    |> where([o: o], o.id != ^option_id)
  end

  defp maybe_exclude_one(query, _), do: query

  # Preloads

  def with_preloads({:ok, %Question{} = q}) do
    {:ok, Repo.preload(q, [:poll, :options])}
  end

  def with_preloads({:ok, %Option{} = q}) do
    {:ok, Repo.preload(q, question: [:poll])}
  end

  def with_preloads({:error, _} = e), do: e
end
