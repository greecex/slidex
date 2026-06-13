defmodule SlidexWeb.PageController do
  use SlidexWeb, :controller

  def home(conn, _params) do
    render(conn, :home,
      poll_count: Slidex.Campaigns.count_polls(),
      vote_count: Slidex.Voting.count_votes()
    )
  end
end
