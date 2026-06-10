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
end
