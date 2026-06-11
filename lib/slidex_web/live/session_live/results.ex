defmodule SlidexWeb.SessionLive.Results do
  @moduledoc """
  Owner-facing results view for a voting session or survey.

  Shows every question with its current tally and the correct option revealed.
  It subscribes to the session room topic, so the owner can watch responses
  arrive live (useful for an open survey) and review the final results after the
  session closes. Owner only; the participant-facing results live on the join
  page.
  """
  use SlidexWeb, :live_view

  alias Slidex.Voting

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@session.title}
        <:subtitle>Results</:subtitle>
        <:actions>
          <.button navigate={~p"/polls/#{@session.poll_id}"}>
            <.icon name="hero-arrow-left" /> Back to poll
          </.button>
        </:actions>
      </.header>

      <div class="mt-4 flex flex-wrap items-center gap-3">
        <div class="badge badge-neutral badge-lg">{status_label(@session)}</div>
        <div class="text-sm text-base-content/70">
          {@total} {if @total == 1, do: "vote", else: "votes"}
        </div>
      </div>

      <div class="mt-8 space-y-8">
        <p :if={@questions == []} class="text-base-content/70">
          This poll has no questions yet.
        </p>

        <div :for={question <- @questions} id={"result-#{question.id}"} class="space-y-3">
          <h2 class="text-xl font-semibold">{question.body}</h2>
          <ul class="space-y-2">
            <li
              :for={option <- question.options}
              class="rounded-lg border border-base-300 bg-base-100 p-3"
            >
              <div class="flex items-center justify-between gap-2">
                <span class="font-medium">
                  {option.body}
                  <span :if={option.is_correct} class="badge badge-success badge-sm">
                    Correct
                  </span>
                </span>
                <span class="text-sm text-base-content/70">
                  {count(@tallies, question.id, option.id)} ({pct(@tallies, question.id, option.id)}%)
                </span>
              </div>
              <progress
                class="progress progress-primary mt-2 w-full"
                value={pct(@tallies, question.id, option.id)}
                max="100"
              >
              </progress>
            </li>
          </ul>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    session = Voting.get_session!(scope, id)

    if connected?(socket), do: Voting.subscribe_session(session)

    {:ok,
     socket
     |> assign(:session, session)
     |> assign(:page_title, session.title)
     |> assign_results(session)}
  end

  @impl true
  def handle_info({:results_updated, _question_id}, socket) do
    {:noreply, assign_results(socket, socket.assigns.session)}
  end

  def handle_info({:state_changed, _state}, socket) do
    session = Voting.get_session!(socket.assigns.current_scope, socket.assigns.session.id)
    {:noreply, socket |> assign(:session, session) |> assign_results(session)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp assign_results(socket, session) do
    tallies = Voting.tally_by_question(session)

    socket
    |> assign(:questions, Voting.list_session_questions(session))
    |> assign(:tallies, tallies)
    |> assign(:total, total_votes(tallies))
  end

  defp total_votes(tallies) do
    tallies |> Map.values() |> Enum.flat_map(&Map.values/1) |> Enum.sum()
  end

  defp count(tallies, question_id, option_id) do
    tallies |> Map.get(question_id, %{}) |> Map.get(option_id, 0)
  end

  defp pct(tallies, question_id, option_id) do
    tally = Map.get(tallies, question_id, %{})
    total = tally |> Map.values() |> Enum.sum()
    if total > 0, do: round(count(tallies, question_id, option_id) / total * 100), else: 0
  end

  defp status_label(%{state: :survey, closed_at: %DateTime{}}), do: "Closed"
  defp status_label(%{state: state}), do: String.capitalize(to_string(state))
end
