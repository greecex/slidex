defmodule SlidexWeb.ConnCase do
  @moduledoc """
  ExUnit case template for tests that drive the endpoint through a `Plug.Conn`.

  Imports `Phoenix.ConnTest`, sets the `@endpoint`, and wraps each test in the
  Ecto SQL sandbox so database changes roll back. Pass `async: true` when the
  test does not rely on shared state.
  """

  use ExUnit.CaseTemplate

  alias Slidex.Accounts.Scope

  using do
    quote do
      # The default endpoint for testing
      @endpoint SlidexWeb.Endpoint

      use SlidexWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import SlidexWeb.ConnCase
    end
  end

  setup tags do
    Slidex.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Setup helper that registers and logs in users.

      setup :register_and_log_in_user

  It stores an updated connection and a registered user in the
  test context.
  """
  def register_and_log_in_user(%{conn: conn} = context) do
    user = Slidex.AccountsFixtures.user_fixture()
    scope = Scope.for_user(user)

    opts =
      context
      |> Map.take([:token_authenticated_at])
      |> Enum.into([])

    %{conn: log_in_user(conn, user, opts), user: user, scope: scope}
  end

  @doc """
  Logs the given `user` into the `conn`.

  It returns an updated `conn`.
  """
  def log_in_user(conn, user, opts \\ []) do
    token = Slidex.Accounts.generate_user_session_token(user)

    maybe_set_token_authenticated_at(token, opts[:token_authenticated_at])

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  defp maybe_set_token_authenticated_at(_token, nil), do: nil

  defp maybe_set_token_authenticated_at(token, authenticated_at) do
    Slidex.AccountsFixtures.override_token_authenticated_at(token, authenticated_at)
  end
end
