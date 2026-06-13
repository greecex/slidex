defmodule Slidex.Campaigns do
  @moduledoc """
  The Campaigns context.
  """

  import Ecto.Query, warn: false
  import Slidex.Authorization
  alias Slidex.{Polling, Preloader, Repo}

  alias Slidex.Accounts.Scope
  alias Slidex.Campaigns.Poll

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
  Returns the total number of polls across all users.

  Used for the public home-page stats, so it is intentionally not scoped.

  ## Examples

      iex> count_polls()
      42

  """
  def count_polls do
    Repo.aggregate(Poll, :count)
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
  def get_poll!(%Scope{} = scope, id, opts \\ []) do
    Poll
    |> Repo.get_by!(id: id, user_id: scope.user.id)
    |> Preloader.with_preloads(opts)
  end

  def get_poll(%Scope{} = scope, id, opts \\ []) do
    Poll
    |> Repo.get_by(id: id, user_id: scope.user.id)
    |> Preloader.with_preloads(opts)
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

  def duplicate_poll(%Scope{} = scope, %Poll{} = poll) do
    :ok = authorize(scope, poll)

    attrs =
      poll
      # :is_public, :access_code,
      |> Map.take([:title, :description])
      |> Map.put(:title, generate_duplicate_title(scope, poll.title))

    with {:ok, copied_poll = %Poll{}} <- create_poll(scope, attrs) do
      copy_poll_questions(copied_poll, poll, scope)
      broadcast_poll(scope, {:duplicated, copied_poll})
      {:ok, copied_poll}
    end
  end

  defp copy_poll_questions(%Poll{} = poll, %Poll{} = original_poll, %Scope{} = scope) do
    original_poll = Repo.preload(original_poll, :questions)
    Enum.each(original_poll.questions, &copy_question(&1, poll, scope))
  end

  defp copy_question(question, %Poll{} = poll, %Scope{} = scope) do
    with {:ok, %Polling.Question{} = copied_question} <-
           Polling.create_question(scope, poll, Map.take(question, [:body, :position])) do
      copied_question = Repo.preload(copied_question, :options)
      Enum.each(question.options, &copy_option(&1, copied_question, scope))
    end
  end

  defp copy_option(option, %Polling.Question{} = question, %Scope{} = scope) do
    Polling.create_option(scope, question, Map.take(option, [:body, :position, :is_correct]))
  end

  defp generate_duplicate_title(%Scope{} = scope, title) do
    common_title = title_without_copy_suffix(title)

    copy_suffix =
      Poll
      |> where([p], p.user_id == ^scope.user.id)
      |> where([p], like(p.title, ^"%#{common_title}%"))
      |> Repo.aggregate(:count)
      |> case do
        1 -> ""
        idx -> " #{idx}"
      end

    "#{common_title} (copy#{copy_suffix})"
  end

  defp title_without_copy_suffix(string) when is_binary(string) do
    ~r/\s+\(copy( \d+)?\)/
    |> Regex.split(string, trim: true)
    |> List.first()
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
    :ok = authorize(scope, poll)

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
    :ok = authorize(scope, poll)

    with {:ok, poll = %Poll{}} <-
           Repo.delete(poll) do
      broadcast_poll(scope, {:deleted, poll})
      {:ok, poll}
    end
  end

  def archive_poll(%Scope{} = scope, %Poll{} = poll) do
    :ok = authorize(scope, poll)

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
    :ok = authorize(scope, poll)

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

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking poll changes.

  ## Examples

      iex> change_poll(scope, poll)
      %Ecto.Changeset{data: %Poll{}}

  """
  def change_poll(%Scope{} = scope, %Poll{} = poll, attrs \\ %{}) do
    :ok = authorize(scope, poll)

    Poll.changeset(poll, attrs, scope)
  end
end
