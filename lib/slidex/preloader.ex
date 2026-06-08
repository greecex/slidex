defmodule Slidex.Preloader do
  @moduledoc """
  Preloading helper functions for Poll, Question, Option
  """
  require Logger
  import Ecto.Query
  alias Slidex.{Repo, Campaigns, Polling, Voting}

  def with_preloads(record_or_list_or_tuple, opts \\ [])

  def with_preloads(records, opts)
      when is_list(records) and is_list(opts) do
    records
    |> Enum.map(& &1.__struct__())
    |> Enum.uniq()
    |> then(fn struct_atoms ->
      case struct_atoms do
        [] ->
          []

        [struct_module] ->
          preload_spec = struct_module |> struct() |> preloads()

          records
          |> Repo.preload(preload_spec)
          |> maybe_sort_questions()

        [_ | _] = _multiple_struct_types ->
          Logger.debug("""
          with_preloads/2 called with opts on a heterogeneous list of structs.
          opts will be ignored; default preloads will be used per struct .
          """)

          Enum.map(records, &with_preloads(&1))
      end
    end)
  end

  def with_preloads(record, opts) when is_struct(record) and is_list(opts) do
    preload_spec = Keyword.get(opts, :preloads, preloads(record))

    if is_list(preload_spec) do
      record
      |> Repo.preload(preload_spec)
      |> maybe_sort_questions()
    else
      record
    end
  end

  def with_preloads(nil, _opts), do: nil

  def with_preloads({:ok, record}, opts)
      when is_struct(record) and is_list(opts),
      do: {:ok, with_preloads(record, opts)}

  def with_preloads({:ok, records}, opts)
      when is_list(records) and is_list(opts),
      do: {:ok, with_preloads(records, opts)}

  def with_preloads({:error, _} = error, _opts), do: error

  # Preload specs

  defp preloads(%Campaigns.Poll{}) do
    [
      [
        questions: [
          options: sorted_options_query()
        ]
      ],
      [:sessions]
    ]
  end

  defp preloads(%Polling.Question{}) do
    [
      :poll,
      options: sorted_options_query()
    ]
  end

  defp preloads(%Polling.Option{}), do: [question: :poll]

  defp preloads(%Voting.Session{}),
    do: [
      :poll,
      [
        current_question: [
          options: sorted_options_query()
        ]
      ]
    ]

  defp sorted_options_query,
    do: from(o in Polling.Option, order_by: [asc: o.position, asc: o.inserted_at])

  defp maybe_sort_questions(records) when is_list(records),
    do: Enum.map(records, &maybe_sort_questions/1)

  defp maybe_sort_questions(%Campaigns.Poll{questions: questions} = poll)
       when is_list(questions),
       do: %{poll | questions: Enum.sort_by(questions, & &1.position)}

  defp maybe_sort_questions(record), do: record
end
