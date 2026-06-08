require Logger

alias Slidex.Repo
alias Slidex.Accounts
alias Slidex.Accounts.{Scope, User}
alias Slidex.Campaigns
alias Slidex.Campaigns.Poll
alias Slidex.Polling
alias Slidex.Polling.{Question, Option}
alias Slidex.Voting
alias Slidex.Voting.{Session}

username = "demo"

{user, scope} =
  case Accounts.get_user_by_email_or_username(username) do
    %User{} = user ->
      Logger.debug("variable 'scope' now contains the scope for user #{username}")
      {user, Accounts.Scope.for_user(user)}

    nil ->
      Logger.warning("""
      Could not create scope for user #{username}.
      No user found with that username.
      Create the user or run the following in the shell to create the 'demo' user:
      mix run priv/repo/seeds.exs
      """)

      {nil, nil}
  end
