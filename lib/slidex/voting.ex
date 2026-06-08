defmodule Slidex.Voting do
  import Ecto.Query
  import Slidex.Preloader
  import Slidex.Authorization

  alias Slidex.{Repo, Preloader}
  alias Slidex.Accounts.Scope
  alias __MODULE__.Session
  alias Slidex.Campaigns.Poll

  def subscribe_sessions(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(Slidex.PubSub, "user:#{key}:sessions")
  end

  defp broadcast_session(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(Slidex.PubSub, "user:#{key}:sessions", message)
  end

  def list_sessions(%Scope{} = scope) do
    scope
    |> query_sessions()
    |> Repo.all()
    |> Preloader.with_preloads()
  end

  def list_sessions(%Scope{} = scope, %Poll{} = poll) do
    scope
    |> query_sessions()
    |> where([s, p], s.poll_id == ^poll.id)
    |> Repo.all()
    |> Preloader.with_preloads()
  end

  defp query_sessions(scope) do
    Session
    |> join(:inner, [s], p in assoc(s, :poll))
    |> where([_s, p], p.user_id == ^scope.user.id)
    |> order_by([s], desc: s.updated_at)
  end

  def get_session!(%Scope{} = scope, id) do
    Session
    |> join(:inner, [s], p in assoc(s, :poll))
    |> where([s, p], p.user_id == ^scope.user.id)
    |> Repo.get!(id)
    |> Preloader.with_preloads()
  end

  def create_session(%Scope{} = scope, %Poll{} = poll, attrs) do
    :ok = authorize(scope, poll)

    %Session{poll_id: poll.id}
    |> Session.changeset(attrs)
    |> Repo.insert()
    |> with_preloads
  end

  def update_session(%Scope{} = scope, %Session{} = session, attrs) do
    :ok = authorize(scope, session)

    with {:ok, session = %Session{}} <-
           session
           |> Session.changeset(attrs)
           |> Repo.update() do
      broadcast_session(scope, {:updated, session})
      {:ok, session}
    end
  end

  def delete_session(%Scope{} = scope, %Session{} = session) do
    :ok = authorize(scope, session)

    Repo.delete(session)
  end

  def change_session(%Scope{} = scope, %Session{} = session, attrs \\ %{}) do
    # Only authorize if the session already belongs to a poll,
    # i.e. when we are editing an existing session, instead of creating a new session
    if session.id do
      :ok = authorize(scope, session)
    end

    Session.changeset(session, attrs)
  end

  def close_session(%Scope{} = scope, %Session{} = session) do
    :ok = authorize(scope, session)

    with %Session{closed_at: nil} <- session,
         attrs = %{closed_at: DateTime.utc_now()},
         {:ok, closed} <-
           scope
           |> change_session(session, attrs)
           |> Repo.update() do
      broadcast_session(scope, {:closed, closed})
      {:ok, closed}
    else
      %Session{closed_at: %DateTime{}} -> {:ok, session}
      error -> error
    end
  end

  def reopen_session(%Scope{} = scope, %Session{} = session) do
    :ok = authorize(scope, session)

    with %Session{closed_at: %DateTime{}} <- session,
         attrs = %{closed_at: nil},
         {:ok, reopened} <-
           scope
           |> change_session(session, attrs)
           |> Repo.update() do
      broadcast_session(scope, {:reopened, reopened})
      {:ok, reopened}
    else
      %Session{closed_at: nil} -> {:ok, session}
      error -> error
    end
  end
end
