defmodule SlidexWeb.VoteLive.Show do
  use SlidexWeb, :live_view

  alias Slidex.Voting

  @impl true
  def mount(%{"id" => voting_session_id}, _session, socket) do
    voting_session = Voting.get_session!(voting_session_id)

    {:ok, socket |> assign(:session, voting_session)}
  end
end
