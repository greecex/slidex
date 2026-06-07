defmodule Slidex.Preloader do
  @moduledoc """
  Preloading helper functions for Poll, Question, Option
  """
  require Logger
  import Ecto.Query
  alias Slidex.{Repo, Campaigns, Polling}

  def with_preloads(record_or_list_or_tuple, opts \\ [])

  def with_preloads(records, opts)
      when is_list(records) and is_list(opts) do
    records
    |> Enum.map(& &1.__struct__())
    |> Enum.uniq()
    |> then(fn struct_atoms ->
      case struct_atoms do
        [atom] ->
          Repo.preload(records, atom |> struct() |> preloads())

        [_ | _] ->
          Logger.debug("""
          with_preloads/2 called with opts on a heterogeneous list of structs.
          opts will be ignored; default preloads per struct will be used.
          """)

          Enum.map(records, &with_preloads(&1))

        [] ->
          []
      end
    end)
  end

  def with_preloads(record, opts)
      when is_struct(record) and is_list(opts) do
    opts
    |> Keyword.get(:preloads, preloads(record))
    |> then(&if(is_list(&1), do: Repo.preload(record, &1), else: record))
  end

  def with_preloads(nil, _opts), do: nil

  def with_preloads({:ok, record}, opts)
      when is_struct(record) and is_list(opts),
      do: {:ok, with_preloads(record, opts)}

  def with_preloads({:ok, records}, opts)
      when is_list(records) and is_list(opts),
      do: {:ok, with_preloads(records, opts)}

  def with_preloads({:error, _} = error, _opts), do: error

  defp preloads(%Campaigns.Poll{}) do
    [
      questions: [
        options: sorted_options_query()
      ]
    ]
  end

  defp preloads(%Polling.Question{}) do
    [
      :poll,
      options: sorted_options_query()
    ]
  end

  defp preloads(%Polling.Option{}) do
    [question: :poll]
  end

  defp sorted_options_query do
    from(o in Polling.Option, order_by: [asc: o.position, asc: o.inserted_at])
  end
end
