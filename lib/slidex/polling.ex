defmodule Slidex.Polling do
  @moduledoc """
  The Polling context.
  """

  import Ecto.Query, warn: false
  alias Slidex.Repo

  alias Slidex.Accounts.Scope
  alias Slidex.Campaigns.Poll

  @doc """
  Returns the list of questions of a %Poll{}.

  ## Examples

      iex> list_questions(scope, poll)
      [%Question{}, ...]

  """
  def list_questions(%Scope{} = scope, %Poll{id: poll_id} = poll) do
    true = poll.user_id == scope.user.id

    Poll
    |> where([q], q.poll_id == ^poll_id)
    |> order_by([q], asc: q.position)
    |> Repo.all()
  end
end
