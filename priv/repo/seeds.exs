# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Slidex.Repo.insert!(%Slidex.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Slidex.Accounts

# Create demo user

attrs = %{
  email: "demo@example.com",
  username: "demo"
}

user =
  with {:ok, u} <- Accounts.register_user(attrs),
       {:ok, {confirmed_user, _}} <- Accounts.confirm_unconfirmed_user(u) do
    confirmed_user
  end
