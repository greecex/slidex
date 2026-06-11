defmodule Slidex.Voting.Tally do
  @moduledoc """
  Pure vote-counting helpers.

  Kept free of database access so the counting logic can be tested with plain
  data. The `Slidex.Voting` context loads the votes and delegates here.
  """

  @doc """
  Counts votes per option id.

  Takes a list of vote-like maps or structs that expose `option_id` and returns
  a map of `option_id => count`. Options with no votes are simply absent.

  ## Examples

      iex> Slidex.Voting.Tally.by_option([%{option_id: 1}, %{option_id: 1}, %{option_id: 2}])
      %{1 => 2, 2 => 1}

      iex> Slidex.Voting.Tally.by_option([])
      %{}

  """
  def by_option(votes) when is_list(votes) do
    Enum.frequencies_by(votes, & &1.option_id)
  end

  @doc """
  The vote count for an option in a tally produced by `by_option/1`. Options
  with no votes count as 0.

  ## Examples

      iex> Slidex.Voting.Tally.count(%{1 => 2, 2 => 1}, 1)
      2

      iex> Slidex.Voting.Tally.count(%{1 => 2}, 99)
      0

  """
  def count(tally, option_id), do: Map.get(tally, option_id, 0)

  @doc """
  The rounded percentage of votes an option holds within a tally. Returns 0
  when the tally is empty.

  ## Examples

      iex> Slidex.Voting.Tally.percentage(%{1 => 3, 2 => 1}, 1)
      75

      iex> Slidex.Voting.Tally.percentage(%{}, 1)
      0

  """
  def percentage(tally, option_id) do
    total = tally |> Map.values() |> Enum.sum()
    if total > 0, do: round(count(tally, option_id) / total * 100), else: 0
  end
end
