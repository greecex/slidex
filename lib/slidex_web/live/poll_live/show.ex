defmodule SlidexWeb.PollLive.Show do
  use SlidexWeb, :live_view

  alias Slidex.{Campaigns, Voting}
  alias Slidex.Campaigns.Poll
  alias Slidex.Repo
  alias SlidexWeb.Components.Timers

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@poll.title}
        <:subtitle>
          <div :if={@poll.archived_at} class="badge badge-warning badge-soft badge-sm">
            <.icon name="hero-archive-box" /> Archived
          </div>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/polls"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/polls/#{@poll}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit poll
          </.button>
        </:actions>
      </.header>

      <p :if={@poll.description}>{@poll.description}</p>

      <div class={[
        "grid grid-cols-1 gap-8 mt-6",
        if(@sessions.voting == [] and @sessions.surveys == [], do: "lg:grid-cols-2")
      ]}>
        <!-- Voting Sessions -->
        <div>
          <div class="flex items-center justify-between mb-3">
            <h3 class="font-semibold flex items-center gap-x-2 w-full justify-between">
              <div>
                Voting sessions
                <span :if={@sessions.voting != []} class="badge badge-md badge-soft">
                  {length(@sessions.voting)}
                </span>
              </div>
              <.add_voting_button
                :if={@sessions.voting !== []}
                poll={@poll}
                disabled={@poll.archived_at}
              />
            </h3>
          </div>

          <%= if @sessions.voting == [] do %>
            <.no_voting_yet poll={@poll} disabled={@poll.archived_at} />
          <% else %>
            <div class="space-y-2">
              <%= for session <- @sessions.voting do %>
                <.session_row session={session} poll={@poll} />
              <% end %>
            </div>
          <% end %>
        </div>
        
    <!-- Survey Sessions -->
        <div>
          <div class="flex items-center justify-between mb-3">
            <h3 class="font-semibold flex items-center gap-x-2 w-full justify-between">
              <div>
                Surveys
                <span :if={@sessions.surveys != []} class="badge badge-md badge-soft">
                  {length(@sessions.surveys)}
                </span>
              </div>
              <.add_survey_button
                :if={@sessions.surveys !== []}
                poll={@poll}
                disabled={@poll.archived_at}
              />
            </h3>
          </div>

          <%= if @sessions.surveys == [] do %>
            <.no_surveys_yet poll={@poll} disabled={@poll.archived_at} />
          <% else %>
            <div class="space-y-2">
              <%= for session <- @sessions.surveys do %>
                <.session_row session={session} poll={@poll} />
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Reusable session row component
  attr :session, :map, required: true
  attr :poll, :map, required: true

  def session_row(assigns) do
    ~H"""
    <div
      id={@session.id}
      class="flex justify-between gap-x-4 rounded-lg border border-base-300 bg-base-100 p-3 ps-4 group hover:bg-base-200 hover:ring-2 hover:ring-primary transition-all items-start"
    >
      <div class="min-w-0 flex-1">
        <div class="font-medium truncate">{@session.title}</div>
        <div class="text-xs text-base-content/60">
          {String.capitalize(to_string(@session.state))}
        </div>
        <div
          :if={@session.closed_at}
          class="tooltip tooltip-sm"
          data-tip={"Closed at #{@session.closed_at}"}
        >
          <.icon name="hero-stop-circle" class="size-5" />
        </div>

        <div
          :if={!@session.closed_at and @poll.questions != []}
          class="tooltip tooltip-sm"
          data-tip="Open for voting"
        >
          <.icon name="hero-play-circle" class="size-5 text-success" />
        </div>

        <div :if={@session.is_public} class="tooltip tooltip-right" data-tip="Public">
          <.icon name="hero-eye" class="size-5 text-info" />
        </div>

        <div
          :if={!is_nil(@session.access_code)}
          class="tooltip tooltip-sm"
          data-tip="Requires access code for participation"
        >
          <.icon name="hero-lock-closed" class="size-5" />
        </div>

        <%= if @session.expires_at do %>
          <span class="text-xs">
            <Timers.expires_at datetime={@session.expires_at} />
          </span>
        <% end %>
      </div>

      <div class="dropdown dropdown-bottom dropdown-end">
        <div tabindex="0" role="button" class="btn btn-ghost p-1">
          <.icon name="hero-ellipsis-vertical" class="size-6" />
        </div>
        <ul
          tabindex="-1"
          class="dropdown-content menu bg-base-100 rounded-box z-1 w-42 p-2 shadow-sm gap-y-2"
        >
          <%= if !@poll.archived_at and !@session.closed_at do %>
            <li>
              <.button
                navigate={~p"/sessions/#{@session}/edit"}
                class="btn btn-primary btn-soft justify-start"
              >
                <.icon name="hero-pencil-square" /> Edit
              </.button>
            </li>

            <div class="divider divider-y my-0" />
          <% end %>

          <li :if={!@session.closed_at}>
            <.button
              phx-click={JS.push("close", value: %{id: @session.id})}
              data-confirm="Are you sure?"
              class="btn btn-soft btn-neutral justify-start"
            >
              <.icon name="hero-stop" /> Close
            </.button>
          </li>

          <li :if={@session.closed_at}>
            <.button
              phx-click={JS.push("reopen", value: %{id: @session.id})}
              data-confirm="Are you sure?"
              class="btn btn-soft btn-success justify-start"
            >
              <.icon name="hero-play" /> Reopen
            </.button>
          </li>

          <li>
            <.button
              phx-click={
                JS.push("delete", value: %{id: @session.id})
                |> JS.hide(to: "##{@session.id}")
                |> JS.hide(to: ".dropdown-content")
              }
              data-confirm="Are you sure?"
              class="btn btn-soft btn-error justify-start"
            >
              <.icon name="hero-trash" /> Delete
            </.button>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Campaigns.subscribe_polls(socket.assigns.current_scope)
    end

    poll =
      socket.assigns.current_scope
      |> Campaigns.get_poll!(id)
      |> Repo.preload(:sessions)

    sessions = group_sessions(poll.sessions || [])

    {:ok,
     socket
     |> assign(:page_title, "Show Poll")
     |> assign(:poll, poll)
     |> assign(:sessions, sessions)}
  end

  defp group_sessions(sessions) do
    Enum.reduce(sessions, %{voting: [], surveys: []}, fn s, acc ->
      if s.state == :survey do
        Map.put(acc, :surveys, acc.surveys ++ [s])
      else
        Map.put(acc, :voting, acc.voting ++ [s])
      end
    end)
  end

  @impl true
  def handle_event("close", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    session = Voting.get_session!(scope, id)
    {:ok, _} = Voting.close_session(scope, session)

    poll =
      socket.assigns.current_scope
      |> Campaigns.get_poll!(socket.assigns.poll.id)
      |> Repo.preload(:sessions)

    sessions = group_sessions(poll.sessions)

    {:noreply, assign(socket, poll: poll, sessions: sessions)}
  end

  @impl true
  def handle_event("reopen", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    session = Voting.get_session!(scope, id)
    {:ok, _} = Voting.reopen_session(scope, session)

    poll =
      socket.assigns.current_scope
      |> Campaigns.get_poll!(socket.assigns.poll.id)
      |> Repo.preload(:sessions)

    sessions = group_sessions(poll.sessions)

    {:noreply, assign(socket, poll: poll, sessions: sessions)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    session = Voting.get_session!(scope, id)
    {:ok, _} = Voting.delete_session(scope, session)

    poll =
      socket.assigns.current_scope
      |> Campaigns.get_poll!(socket.assigns.poll.id)
      |> Repo.preload(:sessions)

    sessions = group_sessions(poll.sessions)

    {:noreply, assign(socket, poll: poll, sessions: sessions)}
  end

  @impl true
  def handle_info({:updated, %Poll{id: id} = poll}, %{assigns: %{poll: %{id: id}}} = socket) do
    {:noreply, assign(socket, :poll, poll)}
  end

  def handle_info({:deleted, %Poll{id: id}}, %{assigns: %{poll: %{id: id}}} = socket) do
    {:noreply,
     socket
     |> put_flash(:error, "The current poll was deleted.")
     |> push_navigate(to: ~p"/polls")}
  end

  def handle_info({type, %Poll{}}, socket)
      when type in [:created, :updated, :deleted, :duplicated] do
    {:noreply, socket}
  end

  def handle_info({:archived, %Poll{} = poll}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "The current poll was archived.")
     |> assign(:poll, poll)}
  end

  def handle_info({:unarchived, %Poll{} = poll}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "The current poll was unarchived.")
     |> assign(:poll, poll)}
  end

  def handle_info({:duplicated, %Poll{} = poll}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "The current poll was duplicated.")
     |> assign(:poll, poll)}
  end

  attr :poll, :map, required: true
  attr :disabled, :boolean, required: false, default: false

  def no_voting_yet(assigns) do
    ~H"""
    <div class="rounded border border-dashed border-base-300 bg-base-200/50 px-4 py-6 text-center">
      <div class="flex flex-col items-center gap-y-3">
        <.icon name="hero-face-frown" class="size-8 text-base-content/50" />
        <p class="text-sm font-semibold">No voting sessions</p>
        <.add_voting_button poll={@poll} disabled={@disabled} />
      </div>
    </div>
    """
  end

  def no_surveys_yet(assigns) do
    ~H"""
    <div class="rounded border border-dashed border-base-300 bg-base-200/50 px-4 py-6 text-center">
      <div class="flex flex-col items-center gap-y-3">
        <.icon name="hero-face-frown" class="size-8 text-base-content/50" />
        <p class="text-sm font-semibold">No surveys</p>
        <.add_survey_button poll={@poll} disabled={@disabled} />
      </div>
    </div>
    """
  end

  def add_voting_button(assigns) do
    ~H"""
    <.button
      navigate={~p"/sessions/new?poll=#{@poll.id}&kind=voting"}
      class="btn btn-outline btn-primary btn-sm"
      disabled={@disabled}
    >
      <.icon name="hero-plus" /> Add Voting
    </.button>
    """
  end

  def add_survey_button(assigns) do
    ~H"""
    <.button
      navigate={~p"/sessions/new?poll=#{@poll.id}&kind=survey"}
      class="btn btn-outline btn-primary btn-sm"
      disabled={@disabled}
    >
      <.icon name="hero-plus" /> Add Survey
    </.button>
    """
  end
end
