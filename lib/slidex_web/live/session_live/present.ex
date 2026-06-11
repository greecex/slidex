defmodule SlidexWeb.SessionLive.Present do
  @moduledoc """
  Presenter (MC) view for a voting session.

  The owner starts the session, advances through the poll's questions one at a
  time, and ends it. Lifecycle and question changes are broadcast on the
  session room topic so participant views (a later batch) stay in sync.
  """
  use SlidexWeb, :live_view

  alias Slidex.{Polling, Presence, Voting}
  alias SlidexWeb.SessionQR

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
        <div id="presence-count" class="badge badge-ghost badge-lg gap-1">
          <.icon name="hero-users" class="size-4" /> {length(@roster.named) + @roster.guests} here
        </div>
      </div>

      <div
        :if={@roster.named != [] or @roster.guests > 0}
        id="presence-roster"
        class="mt-3 flex flex-wrap gap-2"
      >
        <span
          :for={person <- @roster.named}
          class={["badge badge-sm", role_badge_class(person.role)]}
        >
          {person_name(person)}
        </span>
        <span :if={@roster.guests > 0} class="badge badge-sm badge-ghost">
          {guests_label(@roster.guests)}
        </span>
      </div>

      <div
        :if={@session.state != :ended}
        id="session-share"
        class="mt-6 flex flex-col items-center gap-5 rounded-xl border border-base-300 bg-base-100 p-6 text-center"
      >
        <div>
          <div class="text-xl font-semibold text-base-content/80">Scan to join</div>
          <div id="join-qr" class="mt-2">{raw(@qr_svg)}</div>
        </div>
        <div class="space-y-1">
          <div class="text-xl font-semibold text-base-content/80">Or open the link</div>
          <a
            href={@join_url}
            target="_blank"
            class="link link-primary font-mono text-lg font-semibold break-all"
          >
            {@join_url}
          </a>
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
            <div id="current-question" class="space-y-4">
              <div class="text-base text-base-content/60">
                Question {(@current_index || 0) + 1} of {length(@questions)}
              </div>
              <h2 class="text-3xl font-semibold">{@session.current_question.body}</h2>
              <ul class="space-y-3">
                <li
                  :for={option <- @session.current_question.options}
                  class="rounded-lg border border-base-300 bg-base-100 p-4"
                >
                  <div class="flex items-center justify-between gap-2">
                    <span class="text-xl font-medium">
                      {option.body}
                      <span :if={option.is_correct} class="badge badge-success">
                        Correct
                      </span>
                    </span>
                    <span class="text-lg text-base-content/70">
                      {count(@tally, option.id)} ({percentage(@tally, option.id)}%)
                    </span>
                  </div>
                  <progress
                    class="progress progress-primary mt-2 h-4 w-full"
                    value={percentage(@tally, option.id)}
                    max="100"
                  >
                  </progress>
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

    socket =
      socket
      |> assign(:roster, %{named: [], guests: 0})
      |> assign(:join_url, SessionQR.join_url(session))
      |> assign(:qr_svg, SessionQR.svg(session))
      |> assign_session(session, questions)

    if connected?(socket) do
      Voting.subscribe_session(session)

      Presence.track(
        self(),
        Voting.session_topic(session),
        "owner:#{scope.user.id}",
        owner_meta(scope)
      )

      {:ok, assign_presence(socket)}
    else
      {:ok, socket}
    end
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

  def handle_info({:results_updated, _question_id}, socket) do
    {:noreply, assign_tally(socket)}
  end

  def handle_info(%{event: "presence_diff"}, socket) do
    {:noreply, assign_presence(socket)}
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
    |> assign_tally()
  end

  defp assign_tally(socket) do
    session = socket.assigns.session

    tally =
      case session.current_question do
        %{} = question -> Voting.tally(session, question)
        _ -> %{}
      end

    assign(socket, :tally, tally)
  end

  defp assign_presence(socket) do
    roster = Presence.list_present(Voting.session_topic(socket.assigns.session))
    assign(socket, :roster, Presence.summary(roster))
  end

  defp owner_meta(scope) do
    %{
      display_name: scope.user.username,
      role: :owner,
      joined_at: System.system_time(:millisecond)
    }
  end

  defp person_name(%{display_name: name}) when is_binary(name) and name != "", do: name
  defp person_name(%{role: :owner}), do: "Host"
  defp person_name(_person), do: "Guest"

  defp role_badge_class(:owner), do: "badge-primary"
  defp role_badge_class(:user), do: "badge-info"
  defp role_badge_class(_role), do: "badge-ghost"

  defp guests_label(1), do: "1 guest"
  defp guests_label(count), do: "#{count} guests"

  defp count(tally, option_id), do: Map.get(tally, option_id, 0)

  defp percentage(tally, option_id) do
    total = tally |> Map.values() |> Enum.sum()
    if total > 0, do: round(count(tally, option_id) / total * 100), else: 0
  end

  defp current_index(%{current_question_id: nil}, _questions), do: nil

  defp current_index(%{current_question_id: id}, questions),
    do: Enum.find_index(questions, &(&1.id == id))

  defp clamp(value, low, high), do: value |> max(low) |> min(high)

  defp status_label(%{state: :survey, closed_at: %DateTime{}}), do: "Closed"
  defp status_label(%{state: state}), do: String.capitalize(to_string(state))
end
