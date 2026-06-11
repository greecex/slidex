defmodule SlidexWeb.SessionLive.Present do
  @moduledoc """
  Presenter (MC) view for a voting session.

  The owner starts the session, advances through the poll's questions one at a
  time, and ends it. Lifecycle and question changes are broadcast on the
  session room topic so participant views (a later batch) stay in sync.
  """
  use SlidexWeb, :live_view

  alias Slidex.{Polling, Voting}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@session.title}
        <:subtitle>Presenter view</:subtitle>
        <:actions>
          <.button navigate={~p"/polls/#{@session.poll_id}"}>
            <.icon name="hero-arrow-left" /> Back to poll
          </.button>
        </:actions>
      </.header>

      <div class="flex flex-wrap items-center gap-3">
        <div class="badge badge-neutral badge-lg">{status_label(@session)}</div>
        <div :if={@session.access_code} class="text-sm text-base-content/70">
          Access code: <span class="font-mono font-semibold">{@session.access_code}</span>
        </div>
      </div>

      <div class="mt-6 flex flex-row flex-wrap gap-2">
        <.button
          :if={@session.state == :pending}
          id="start-session"
          phx-click="start"
          variant="primary"
        >
          <.icon name="hero-play" /> Start
        </.button>

        <%= if @session.state == :active do %>
          <.button id="prev-question" phx-click="prev" disabled={@current_index in [nil, 0]}>
            <.icon name="hero-chevron-left" /> Previous
          </.button>
          <.button
            id="next-question"
            phx-click="next"
            disabled={is_nil(@current_index) or @current_index >= length(@questions) - 1}
          >
            Next <.icon name="hero-chevron-right" />
          </.button>
          <.button
            id="end-session"
            phx-click="end"
            data-confirm="End this session?"
            class="btn btn-soft btn-error"
          >
            <.icon name="hero-stop" /> End
          </.button>
        <% end %>
      </div>

      <div class="mt-8">
        <%= cond do %>
          <% @session.state == :survey -> %>
            <p class="text-base-content/70">Surveys are self-paced and are not presented.</p>
          <% @session.state == :pending -> %>
            <p class="text-base-content/70">Press Start to begin the session.</p>
          <% @session.state == :ended -> %>
            <p class="text-base-content/70">This session has ended.</p>
          <% @session.current_question -> %>
            <div id="current-question" class="space-y-3">
              <div class="text-sm text-base-content/60">
                Question {(@current_index || 0) + 1} of {length(@questions)}
              </div>
              <h2 class="text-2xl font-semibold">{@session.current_question.body}</h2>
              <ul class="space-y-2">
                <li
                  :for={option <- @session.current_question.options}
                  class="rounded-lg border border-base-300 bg-base-100 p-3"
                >
                  {option.body}
                </li>
              </ul>
            </div>
          <% true -> %>
            <p class="text-base-content/70">No question selected yet.</p>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    session = Voting.get_session!(scope, id)
    questions = Polling.list_questions(scope, session.poll)

    if connected?(socket), do: Voting.subscribe_session(session)

    {:ok, assign_session(socket, session, questions)}
  end

  @impl true
  def handle_event("start", _params, socket) do
    scope = socket.assigns.current_scope
    {:ok, session} = Voting.start_session(scope, socket.assigns.session)
    maybe_set_first_question(scope, session, socket.assigns.questions)

    {:noreply, refresh(socket)}
  end

  def handle_event("end", _params, socket) do
    {:ok, _} = Voting.close_session(socket.assigns.current_scope, socket.assigns.session)
    {:noreply, refresh(socket)}
  end

  def handle_event("next", _params, socket), do: {:noreply, move_question(socket, 1)}
  def handle_event("prev", _params, socket), do: {:noreply, move_question(socket, -1)}

  @impl true
  def handle_info({event, _payload}, socket) when event in [:state_changed, :question_changed] do
    {:noreply, refresh(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp move_question(socket, delta) do
    %{questions: questions, current_index: index, current_scope: scope, session: session} =
      socket.assigns

    target = clamp((index || 0) + delta, 0, max(length(questions) - 1, 0))

    case Enum.at(questions, target) do
      nil ->
        socket

      question ->
        {:ok, _} = Voting.set_current_question(scope, session, question)
        refresh(socket)
    end
  end

  defp maybe_set_first_question(scope, %{current_question_id: nil} = session, [first | _]) do
    Voting.set_current_question(scope, session, first)
  end

  defp maybe_set_first_question(_scope, _session, _questions), do: :ok

  defp refresh(socket) do
    scope = socket.assigns.current_scope
    session = Voting.get_session!(scope, socket.assigns.session.id)
    assign_session(socket, session, socket.assigns.questions)
  end

  defp assign_session(socket, session, questions) do
    socket
    |> assign(:session, session)
    |> assign(:questions, questions)
    |> assign(:current_index, current_index(session, questions))
    |> assign(:page_title, session.title)
  end

  defp current_index(%{current_question_id: nil}, _questions), do: nil

  defp current_index(%{current_question_id: id}, questions),
    do: Enum.find_index(questions, &(&1.id == id))

  defp clamp(value, low, high), do: value |> max(low) |> min(high)

  defp status_label(%{state: :survey, closed_at: %DateTime{}}), do: "Closed"
  defp status_label(%{state: state}), do: String.capitalize(to_string(state))
end
