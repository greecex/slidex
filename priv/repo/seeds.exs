# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# In a release (production), run it once with:
#
#     bin/slidex eval "Slidex.Release.seed()"
#
# Seeding is idempotent: existing users are left untouched.

alias Slidex.Accounts

seed_user = fn email, username ->
  case Accounts.get_user_by_email(email) do
    nil ->
      {:ok, user} = Accounts.register_user(%{email: email, username: username})
      {:ok, {confirmed_user, _expired_tokens}} = Accounts.confirm_unconfirmed_user(user)
      confirmed_user

    user ->
      user
  end
end

# The owner account, seeded in every environment. Magic-link login only, no password.
seed_user.("petros@amignosis.com", "petros")

# A demo account, useful only for local development.
if Application.get_env(:slidex, :dev_routes, false) do
  seed_user.("demo@example.com", "demo")
end
