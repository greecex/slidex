defmodule Slidex.Polling.Reorder do
  @moduledoc """
  Module that handles the reordering of questions and options
  """

  import Ecto.Query
  alias Slidex.Accounts.Scope
  alias Slidex.{Authorization, Repo}
  alias Slidex.Polling.{Option, Question}

  @doc """
  Moves an option one step higher or lower within its question,
  (or a question within its poll).

  Always re-normalizes positions afterward for stability.
  """

  def move(%Scope{} = scope, record, direction)
      when (is_struct(record, Question) or
              is_struct(record, Option)) and
             direction in [:higher, :lower] do
    :ok = Authorization.authorize(scope, record)

    siblings = siblings(record)
    current_index = Enum.find_index(siblings, &(&1.id == record.id))
    new_index = new_index(current_index, direction, siblings)

    if is_nil(new_index) do
      {:ok, :unchanged}
    else
      swap(current_index, new_index, siblings)
    end
  end

  # List all siblings ordered by current position
  defp siblings(record) do
    record
    |> by_parent_id()
    |> order_by([o], asc: o.position, asc: o.inserted_at)
    |> Repo.all()
  end

  defp by_parent_id(%Question{} = question),
    do: where(Question, [q], q.poll_id == ^question.poll_id)

  defp by_parent_id(%Option{} = option),
    do: where(Option, [o], o.question_id == ^option.question_id)

  # Calculate new index based on current index, direction of reordering, and siblings
  defp new_index(current_index, direction, siblings)
       when is_list(siblings) and direction in [:lower, :higher] do
    case {direction, current_index} do
      {:higher, nil} -> nil
      {:higher, 0} -> nil
      {:higher, i} -> i - 1
      {:lower, nil} -> nil
      {:lower, i} when i == length(siblings) - 1 -> nil
      {:lower, i} -> i + 1
    end
  end

  # Swap in the list
  defp swap(current_index, new_index, siblings) do
    {moved, rest} = List.pop_at(siblings, current_index)
    siblings = List.insert_at(rest, new_index, moved)

    # Re-assign clean sequential positions
    Repo.transaction(fn ->
      siblings
      |> Enum.with_index()
      |> Enum.each(&reposition/1)
    end)

    {:ok, :reordered}
  end

  defp reposition({record, index}) do
    if record.position != index do
      record
      |> Ecto.Changeset.change(position: index)
      |> Repo.update!()
    end
  end
end
