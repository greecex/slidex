defmodule Slidex.Search do
  @moduledoc """
  Search across `%Question{}` and `%Option{}` records' `:body` values
  with support for optionally excluding specific records from the search.

  This module is used by the `QuestionLive` and `OptionLive` LiveComponents'
  `:body` input field to present a dropdown with found values for
  convenient pre-filling of existing question or option `:body` values.
  """
  import Ecto.Query
  alias Slidex.{Repo, Accounts, Campaigns, Polling}

  @limit 5

  def question_body(%Accounts.Scope{} = scope, search_term, opts \\ []) do
    limit = Keyword.get(opts, :limit, @limit)
    excluded = Keyword.get(opts, :excluded, [])

    from(Polling.Question, as: :q)
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

  def option_body(%Accounts.Scope{} = scope, search_term, opts \\ []) do
    limit = Keyword.get(opts, :limit, @limit)
    excluded = Keyword.get(opts, :excluded, [])

    from(Polling.Option, as: :o)
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

  # Exclusion query helpers

  defp maybe_exclude_many(query, list) when is_list(list),
    do: Enum.reduce(list, query, fn x, acc -> maybe_exclude_one(acc, x) end)

  defp maybe_exclude_many(query, _), do: query

  defp maybe_exclude_one(query, %Campaigns.Poll{id: poll_id}),
    do: where(query, [p: p], p.id != ^poll_id)

  defp maybe_exclude_one(query, %Polling.Question{id: question_id}),
    do: where(query, [q: q], q.id != ^question_id)

  defp maybe_exclude_one(query, %Polling.Option{id: option_id}),
    do: where(query, [o: o], o.id != ^option_id)

  defp maybe_exclude_one(query, _), do: query
end
