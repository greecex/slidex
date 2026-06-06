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

# Create demo user

%{
  email: "demo@example.com",
  username: "demo",
  confirmed_at: DateTime.utc_now()
}
|> Slidex.Accounts.register_user()
