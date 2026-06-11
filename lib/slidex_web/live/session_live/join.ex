defmodule SlidexWeb.SessionLive.Join do
  @moduledoc """
  Public participant view for a session.

  Anyone with the slug link can join; guests are allowed for public sessions,
  while a non-public session requires a logged in user. The view shows the
  current question (voting) or every question (survey) and lets the participant
  vote. Results are presenter-only and are not shown here.
  """
  use SlidexWeb, :live_view

  alias Slidex.Voting

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@session.title}
        <:subtitle :if={@session.description}>{@session.description}</:subtitle>
      </.header>

      <%= cond do %>
        <% @closed -> %>
          <p class="mt-6 text-base-content/70">This session has ended.</p>
        <% @questions == [] -> %>
          <p class="mt-6 text-base-content/70">Waiting for the host to start the session...</p>
        <% true -> %>
          <div :for={question <- @questions} id={"question-#{question.id}"} class="mt-8 space-y-3">
            <h2 class="text-xl font-semibold">{question.body}</h2>
            <div class="flex flex-col gap-2">
              <.button
                :for={option <- question.options}
                id={"option-#{option.id}"}
                phx-click="vote"
                phx-value-question={question.id}
                phx-value-option={option.id}
                class={[
                  "btn justify-start",
                  if(@votes[question.id] == option.id, do: "btn-primary", else: "btn-soft")
                ]}
              >
                {option.body}
              </.button>
            </div>
          </div>
      <% end %>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"slug" => slug}, session, socket) do
    case Voting.get_session_by_slug(slug) do
      nil ->
        {:ok, socket |> put_flash(:error, "That session was not found.") |> redirect(to: ~p"/")}

      record ->
        join(socket, record, session["participant_token"])
    end
  end

  defp join(socket, session, token) do
    cond do
      requires_login?(session, socket.assigns.current_scope) ->
        {:ok,
         socket
         |> put_flash(:error, "Please log in to join this session.")
         |> redirect(to: ~p"/users/log-in")}

      not joinable?(session) ->
        {:ok,
         socket
         |> assign(:page_title, session.title)
         |> assign(session: session, closed: true, questions: [], votes: %{}, participant: nil)}

      true ->
        {:ok, participant} =
          Voting.find_or_create_participant(
            session,
            token,
            participant_attrs(socket.assigns.current_scope)
          )

        if connected?(socket), do: Voting.subscribe_session(session)

        {:ok, assign_state(socket, session, participant)}
    end
  end

  @impl true
  def handle_event("vote", %{"question" => question_id, "option" => option_id}, socket) do
    with question when not is_nil(question) <-
           Enum.find(socket.assigns.questions, &(&1.id == question_id)),
         option when not is_nil(option) <- Enum.find(question.options, &(&1.id == option_id)),
         {:ok, _vote} <-
           Voting.cast_vote(socket.assigns.session, socket.assigns.participant, question, option) do
      votes = Voting.list_participant_votes(socket.assigns.session, socket.assigns.participant)
      {:noreply, assign(socket, :votes, votes)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not record your vote.")}
    end
  end

  @impl true
  def handle_info({event, _payload}, socket) when event in [:state_changed, :question_changed] do
    {:noreply, refresh(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp refresh(socket) do
    session = Voting.get_session_by_slug(socket.assigns.session.slug)
    assign_state(socket, session, socket.assigns.participant)
  end

  defp assign_state(socket, session, participant) do
    votes = if participant, do: Voting.list_participant_votes(session, participant), else: %{}

    socket
    |> assign(:session, session)
    |> assign(:participant, participant)
    |> assign(:closed, not joinable?(session))
    |> assign(:questions, questions_to_show(session))
    |> assign(:votes, votes)
    |> assign(:page_title, session.title)
  end

  defp questions_to_show(%{state: :active, current_question: %{} = question}), do: [question]

  defp questions_to_show(%{state: :survey} = session) do
    if joinable?(session), do: Voting.list_session_questions(session), else: []
  end

  defp questions_to_show(_session), do: []

  defp joinable?(session), do: not closed?(session) and not expired?(session)

  defp closed?(%{state: :ended}), do: true
  defp closed?(%{closed_at: %DateTime{}}), do: true
  defp closed?(_session), do: false

  defp expired?(%{expires_at: %DateTime{} = at}),
    do: DateTime.compare(at, DateTime.utc_now()) != :gt

  defp expired?(_session), do: false

  defp requires_login?(%{is_public: true}, _scope), do: false
  defp requires_login?(_session, %{user: %_{}}), do: false
  defp requires_login?(_session, _scope), do: true

  defp participant_attrs(%{user: %{id: id, username: username}}),
    do: %{user_id: id, display_name: username}

  defp participant_attrs(_scope), do: %{}
end
