defmodule Slidex.Voting do
  import Ecto.Query
  import Slidex.Preloader
  import Slidex.Authorization
  alias Slidex.{Repo, Preloader}
  alias Slidex.Accounts.Scope
  alias __MODULE__.Session
  alias Slidex.Campaigns.Poll

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

  def get_session!(id) do
    Session
    |> Repo.get_by!(id: id)
    |> Preloader.with_preloads()
  end

  def create_session(%Scope{} = scope, %Poll{} = poll, attrs) do
    :ok = authorize(scope, poll)

    %Session{poll_id: poll.id}
    |> Session.changeset(attrs)
    |> Repo.insert()
    |> with_preloads
  end

  def delete_session(%Scope{} = scope, %Session{} = session) do
    :ok = authorize(scope, session)

    Repo.delete(session)
  end

  def change_session(%Scope{} = scope, %Session{} = session, attrs \\ %{}) do
    # Only authorize if the session already belongs to a poll
    if session.poll_id do
      :ok = authorize(scope, session)
    end

    Session.changeset(session, attrs)
  end
end
