defmodule SlidexWeb.PollLive.Index do
  use SlidexWeb, :live_view

  alias Slidex.Campaigns
  alias SlidexWeb.Components.Timers

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Listing Polls
        <:actions>
          <.button variant="primary" navigate={~p"/polls/new"}>
            <.icon name="hero-plus" /> New Poll
          </.button>
        </:actions>
      </.header>

      <.table
        id="polls"
        rows={@streams.polls}
        row_click={fn {_id, poll} -> JS.navigate(~p"/polls/#{poll}") end}
      >
        <:col :let={{_id, poll}} label="">
          <div
            :if={poll.closed_at}
            class="tooltip tooltip-sm"
            data-tip={"Closed at #{poll.closed_at}"}
          >
            <.icon name="hero-stop-circle" class="size-5" />
          </div>

          <div :if={!poll.closed_at} class="tooltip tooltip-sm" data-tip="Still open for voting">
            <.icon name="hero-play-circle" class="size-5" />
          </div>
        </:col>

        <:col :let={{_id, poll}} label="">
          <%= if poll.is_public do %>
            <div class="tooltip" data-tip="Public">
              <.icon name="hero-eye" class="size-5" />
            </div>
          <% end %>
        </:col>

        <:col :let={{_id, poll}} label="">
          <div
            :if={!is_nil(poll.access_code)}
            class="tooltip tooltip-sm"
            data-tip="Requires access code for participation"
          >
            <.icon name="hero-lock-closed" class="size-5" />
          </div>
        </:col>

        <:col :let={{_id, poll}} label="Title">{poll.title}</:col>

        <:col :let={{_id, poll}} label="Expires at">
          <%= if poll.expires_at do %>
            <Timers.expires_at datetime={poll.expires_at} />
          <% else %>
            -
          <% end %>
        </:col>

        <:action :let={{id, poll}}>
          <div class="sr-only">
            <.link navigate={~p"/polls/#{poll}"}>Show</.link>
          </div>
          <div class="dropdown dropdown-bottom dropdown-end">
            <div tabindex="0" role="button" class="btn btn-ghost">
              <.icon name="hero-ellipsis-vertical" class="size-6" />
            </div>
            <ul
              tabindex="-1"
              class="dropdown-content menu bg-base-100 rounded-box z-1 w-42 p-2 shadow-sm gap-y-1"
            >
              <li>
                <.button
                  navigate={~p"/polls/#{poll}/edit"}
                  class="btn btn-primary btn-soft justify-start"
                >
                  <.icon name="hero-pencil-square" /> <span class="hidden md:block">Edit</span>
                </.button>
              </li>
              <li>
                <.button
                  navigate={~p"/polls/#{poll}/questions"}
                  class="btn btn-neutral btn-soft justify-start"
                >
                  <.icon name="hero-question-mark-circle" />
                  <span class="hidden md:block">Questions</span>
                </.button>
              </li>
              <li>
                <.button
                  phx-click={JS.push("delete", value: %{id: poll.id}) |> hide("##{id}")}
                  data-confirm="Are you sure?"
                  class="btn btn-soft btn-error justify-start"
                >
                  <.icon name="hero-trash" /> <span class="hidden md:block">Delete</span>
                </.button>
              </li>
            </ul>
          </div>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Campaigns.subscribe_polls(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Listing Polls")
     |> stream(:polls, list_polls(socket.assigns.current_scope))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    poll = Campaigns.get_poll!(socket.assigns.current_scope, id)
    {:ok, _} = Campaigns.delete_poll(socket.assigns.current_scope, poll)

    {:noreply, stream_delete(socket, :polls, poll)}
  end

  @impl true
  def handle_info({type, %Slidex.Campaigns.Poll{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply, stream(socket, :polls, list_polls(socket.assigns.current_scope), reset: true)}
  end

  defp list_polls(current_scope) do
    Campaigns.list_polls(current_scope)
  end
end
