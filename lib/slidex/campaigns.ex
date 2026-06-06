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
  def list_polls(%Scope{} = scope, opts \\ []) do
    preloads = Keyword.get(opts, :preloads, [])

    query =
      Poll
      |> where([p], p.user_id == ^scope.user.id)
      |> order_by([p], desc: p.inserted_at)

    case Keyword.get(opts, :archived, false) do
      true -> query
      false -> query |> where([p], is_nil(p.archived_at))
      :only -> query |> where([p], not is_nil(p.archived_at))
    end
    |> Repo.all()
    |> Repo.preload(preloads)
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
  def get_poll!(%Scope{} = scope, id, preloads \\ []) do
    Poll
    |> Repo.get_by!(id: id, user_id: scope.user.id)
    |> Repo.preload(preloads)
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

  def archive_poll(%Scope{} = scope, %Poll{} = poll) do
    true = poll.user_id == scope.user.id

    with %Poll{archived_at: nil} <- poll,
         attrs = %{archived_at: DateTime.utc_now()},
         {:ok, archived} <-
           scope
           |> change_poll(poll, attrs)
           |> Repo.update() do
      broadcast_poll(scope, {:archived, archived})
      {:ok, archived}
    else
      %Poll{archived_at: %DateTime{}} -> {:ok, poll}
      error -> error
    end
  end

  def unarchive_poll(%Scope{} = scope, %Poll{} = poll) do
    true = poll.user_id == scope.user.id

    with %Poll{archived_at: %DateTime{}} <- poll,
         attrs = %{archived_at: nil},
         {:ok, unarchived} <-
           scope
           |> change_poll(poll, attrs)
           |> Repo.update() do
      broadcast_poll(scope, {:unarchived, unarchived})
      {:ok, unarchived}
    else
      %Poll{archived_at: nil} -> {:ok, poll}
      error -> error
    end
  end

  def close_poll(%Scope{} = scope, %Poll{} = poll) do
    true = poll.user_id == scope.user.id

    with %Poll{closed_at: nil} <- poll,
         attrs = %{closed_at: DateTime.utc_now()},
         {:ok, closed} <-
           scope
           |> change_poll(poll, attrs)
           |> Repo.update() do
      broadcast_poll(scope, {:closed, closed})
      {:ok, closed}
    else
      %Poll{closed_at: %DateTime{}} -> {:ok, poll}
      error -> error
    end
  end

  def reopen_poll(%Scope{} = scope, %Poll{} = poll) do
    true = poll.user_id == scope.user.id

    with %Poll{closed_at: %DateTime{}} <- poll,
         attrs = %{closed_at: nil},
         {:ok, reopened} <-
           scope
           |> change_poll(poll, attrs)
           |> Repo.update() do
      broadcast_poll(scope, {:reopened, reopened})
      {:ok, reopened}
    else
      %Poll{closed_at: nil} -> {:ok, poll}
      error -> error
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
