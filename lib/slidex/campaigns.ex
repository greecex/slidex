defmodule Slidex.Campaigns do
  @moduledoc """
  The Campaigns context.
  """

  import Ecto.Query, warn: false
  alias Slidex.Repo

  alias Slidex.Campaigns.Poll
  alias Slidex.Accounts.Scope

  @doc """
  Subscribes to scoped notifications about any poll changes.

  The broadcasted messages match the pattern:

    * {:created, %Poll{}}
    * {:updated, %Poll{}}
    * {:deleted, %Poll{}}

  """
  def subscribe_polls(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(Slidex.PubSub, "user:#{key}:polls")
  end

  defp broadcast_poll(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(Slidex.PubSub, "user:#{key}:polls", message)
  end

  @doc """
  Returns the list of polls.

  ## Examples

      iex> list_polls(scope)
      [%Poll{}, ...]

  """
  def list_polls(%Scope{} = scope) do
    Repo.all_by(Poll, user_id: scope.user.id)
  end

  @doc """
  Gets a single poll.

  Raises `Ecto.NoResultsError` if the Poll does not exist.

  ## Examples

      iex> get_poll!(scope, 123)
      %Poll{}

      iex> get_poll!(scope, 456)
      ** (Ecto.NoResultsError)

  """
  def get_poll!(%Scope{} = scope, id) do
    Repo.get_by!(Poll, id: id, user_id: scope.user.id)
  end

  @doc """
  Creates a poll.

  ## Examples

      iex> create_poll(scope, %{field: value})
      {:ok, %Poll{}}

      iex> create_poll(scope, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_poll(%Scope{} = scope, attrs) do
    with {:ok, poll = %Poll{}} <-
           %Poll{}
           |> Poll.changeset(attrs, scope)
           |> Repo.insert() do
      broadcast_poll(scope, {:created, poll})
      {:ok, poll}
    end
  end

  @doc """
  Updates a poll.

  ## Examples

      iex> update_poll(scope, poll, %{field: new_value})
      {:ok, %Poll{}}

      iex> update_poll(scope, poll, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_poll(%Scope{} = scope, %Poll{} = poll, attrs) do
    true = poll.user_id == scope.user.id

    with {:ok, poll = %Poll{}} <-
           poll
           |> Poll.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_poll(scope, {:updated, poll})
      {:ok, poll}
    end
  end

  @doc """
  Deletes a poll.

  ## Examples

      iex> delete_poll(scope, poll)
      {:ok, %Poll{}}

      iex> delete_poll(scope, poll)
      {:error, %Ecto.Changeset{}}

  """
  def delete_poll(%Scope{} = scope, %Poll{} = poll) do
    true = poll.user_id == scope.user.id

    with {:ok, poll = %Poll{}} <-
           Repo.delete(poll) do
      broadcast_poll(scope, {:deleted, poll})
      {:ok, poll}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking poll changes.

  ## Examples

      iex> change_poll(scope, poll)
      %Ecto.Changeset{data: %Poll{}}

  """
  def change_poll(%Scope{} = scope, %Poll{} = poll, attrs \\ %{}) do
    true = poll.user_id == scope.user.id

    Poll.changeset(poll, attrs, scope)
  end
end
