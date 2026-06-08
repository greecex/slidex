defmodule SlidexWeb.PollLive.Show do
  use SlidexWeb, :live_view

  alias Slidex.Campaigns

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@poll.title}
        <:subtitle>This is a poll record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/polls"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/polls/#{@poll}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit poll
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Is public">{@poll.is_public}</:item>
        <:item title="Access code">{@poll.access_code}</:item>
        <:item title="Expires at">{@poll.expires_at}</:item>
        <:item title="Closed at">{@poll.closed_at}</:item>
        <:item title="Archived at">{@poll.archived_at}</:item>
      </.list>

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-6">
        
    <!-- Voting -->
        <div class="space-y-2">
          <h3 class="font-semibold">
            Voting sessions
            <div :if={@sessions.voting != []} class="badge badge-md badge-soft">
              {length(@sessions.voting)}
            </div>
          </h3>
          <%= if @sessions.voting == [] do %>
            <.no_voting_yet />
          <% else %>
            <div class="p-3 bg-base-100">
              <%= for s <- @sessions.voting do %>
                <div>{s.title}</div>
              <% end %>
            </div>
          <% end %>
        </div>
        
    <!-- Surveys -->
        <div class="space-y-2">
          <h3 class="font-semibold">
            Surveys
            <div :if={@sessions.surveys != []} class="badge badge-md badge-soft">
              {length(@sessions.surveys)}
            </div>
          </h3>
          <%= if @sessions.surveys == [] do %>
            <.no_surveys_yet />
          <% else %>
            <div class="p-3 bg-base-100">
              <%= for s <- @sessions.surveys do %>
                <div>{s.title}</div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Campaigns.subscribe_polls(socket.assigns.current_scope)
    end

    poll = Campaigns.get_poll!(socket.assigns.current_scope, id)

    sessions =
      Enum.reduce(poll.sessions, %{voting: [], surveys: []}, fn s, acc ->
        if s.is_survey do
          Map.put(acc, :surveys, acc.surveys ++ [s])
        else
          Map.put(acc, :voting, acc.voting ++ [s])
        end
      end)

    {:ok,
     socket
     |> assign(:page_title, "Show Poll")
     |> assign(:poll, poll)
     |> assign(:sessions, sessions)}
  end

  @impl true
  def handle_info(
        {:updated, %Slidex.Campaigns.Poll{id: id} = poll},
        %{assigns: %{poll: %{id: id}}} = socket
      ) do
    {:noreply, assign(socket, :poll, poll)}
  end

  def handle_info(
        {:deleted, %Slidex.Campaigns.Poll{id: id}},
        %{assigns: %{poll: %{id: id}}} = socket
      ) do
    {:noreply,
     socket
     |> put_flash(:error, "The current poll was deleted.")
     |> push_navigate(to: ~p"/polls")}
  end

  def handle_info({type, %Slidex.Campaigns.Poll{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply, socket}
  end

  def no_voting_yet(assigns) do
    ~H"""
    <div class="rounded border border-dashed border-base-300 bg-base-200/50 px-4 py-5">
      <div class="flex flex-col items-center text-center gap-y-3">
        <div class="flex flex-row items-center justify-center gap-x-2">
          <.icon
            name="hero-face-frown"
            class="size-8 text-base-content/50"
          />
          <p class="text-sm font-semibold text-base-content">No voting sessions added yet!</p>
        </div>

        <.add_voting_button />
      </div>
    </div>
    """
  end

  def no_surveys_yet(assigns) do
    ~H"""
    <div class="rounded border border-dashed border-base-300 bg-base-200/50 px-4 py-5">
      <div class="flex flex-col items-center text-center gap-y-3">
        <div class="flex flex-row items-center justify-center gap-x-2">
          <.icon
            name="hero-face-frown"
            class="size-8 text-base-content/50"
          />
          <p class="text-sm font-semibold text-base-content">No surveys added yet!</p>
        </div>

        <.add_voting_button />
      </div>
    </div>
    """
  end

  def add_voting_button(assigns) do
    ~H"""
    <.button
      phx-click="add_voting"
      class={["btn btn-outline btn-primary btn-sm"]}
    >
      <.icon name="hero-plus" /> Add Voting
    </.button>
    """
  end

  def add_surve_button(assigns) do
    ~H"""
    <.button
      phx-click="add_survey"
      class={["btn btn-outline btn-primary btn-sm"]}
    >
      <.icon name="hero-plus" /> Add Survey
    </.button>
    """
  end
end
