defmodule SlidexWeb.PollLive.Index do
  use SlidexWeb, :live_view

  alias Slidex.Campaigns
  alias Slidex.Campaigns.Poll
  alias SlidexWeb.Components.Timers

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        <div class="flex flex-row gap-x-2 items-center justify-start">
          <div class="text-2xl">Polls</div>
          <div class="badge badge-primary badge-soft badge-md">{@count}</div>
        </div>
        <:actions>
          <.button variant="primary" navigate={~p"/polls/new"}>
            <.icon name="hero-plus" /> New Poll
          </.button>
        </:actions>
      </.header>

      <div class="dropdown dropdown-bottom dropdown-start">
        <div tabindex="0" role="button" class="btn btn-neutral">
          <.icon name="hero-funnel" class="size-6" />
          {filter_label(@archived)}
        </div>
        <ul
          tabindex="-1"
          class="dropdown-content menu bg-base-100 rounded-box z-1 w-42 p-2 shadow-sm gap-y-2"
        >
          <li>
            <.button
              navigate={~p"/polls?archived=true"}
              class="btn btn-ghost justify-start"
            >
              <.icon name="hero-list-bullet" /> All
            </.button>
          </li>
          <li>
            <.button
              navigate={~p"/polls?archived=false"}
              class="btn btn-ghost justify-start"
            >
              <.icon name="hero-list-bullet" /> Not archived
            </.button>
          </li>
          <li>
            <.button
              navigate={~p"/polls?archived=only"}
              class="btn btn-ghost justify-start"
            >
              <.icon name="hero-archive-box" /> Archived only
            </.button>
          </li>
        </ul>
      </div>

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

          <div
            :if={!poll.closed_at and poll.questions != []}
            class="tooltip tooltip-sm"
            data-tip="Open for voting"
          >
            <.icon name="hero-play-circle" class="size-5 text-success" />
          </div>

          <div
            :if={!poll.closed_at and poll.questions == []}
            class="tooltip tooltip-sm"
            data-tip="No questions defined"
          >
            <.icon name="hero-exclamation-triangle" class="size-5 text-warning" />
          </div>
        </:col>

        <:col :let={{_id, poll}} label="">
          <%= if poll.is_public do %>
            <div class="tooltip" data-tip="Public">
              <.icon name="hero-eye" class="size-5 text-info" />
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

        <:col :let={{_id, poll}} label="Title">
          <div class="flex flex-row items-center justify-start gap-x-2">
            <div :if={poll.archived_at} class="badge badge-warning badge-soft badge-sm">
              <.icon name="hero-archive-box" /> Archived
            </div>
            <span class="font-bold">{poll.title}</span>
          </div>
        </:col>

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
              class="dropdown-content menu bg-base-100 rounded-box z-1 w-42 p-2 shadow-sm gap-y-2"
            >
              <%= if !poll.archived_at do %>
                <li>
                  <.button
                    navigate={~p"/polls/#{poll}/edit"}
                    class="btn btn-primary btn-soft justify-start"
                  >
                    <.icon name="hero-pencil-square" /> Edit
                  </.button>
                </li>

                <li>
                  <.button
                    navigate={~p"/polls/#{poll}/questions"}
                    class="btn btn-neutral btn-soft justify-start"
                  >
                    <.icon name="hero-question-mark-circle" /> Questions
                  </.button>
                </li>

                <div class="divider divider-y my-0" />

                <li :if={!poll.closed_at}>
                  <.button
                    phx-click={JS.push("close", value: %{id: poll.id})}
                    data-confirm="Are you sure?"
                    class="btn btn-soft btn-neutral justify-start"
                  >
                    <.icon name="hero-stop" /> Close
                  </.button>
                </li>

                <li :if={poll.closed_at}>
                  <.button
                    phx-click={JS.push("reopen", value: %{id: poll.id})}
                    data-confirm="Are you sure?"
                    class="btn btn-soft btn-success justify-start"
                  >
                    <.icon name="hero-play" /> Reopen
                  </.button>
                </li>
              <% end %>

              <li>
                <.button
                  phx-click={JS.push("duplicate", value: %{id: poll.id})}
                  data-confirm="Are you sure?"
                  class="btn btn-soft btn-neutral justify-start"
                >
                  <.icon name="hero-document-duplicate" /> Duplicate
                </.button>
              </li>

              <li :if={!poll.archived_at}>
                <.button
                  phx-click={JS.push("archive", value: %{id: poll.id}) |> hide("##{id}")}
                  data-confirm="Are you sure?"
                  class="btn btn-soft btn-warning justify-start"
                >
                  <.icon name="hero-archive-box-arrow-down" /> Archive
                </.button>
              </li>

              <li :if={poll.archived_at}>
                <.button
                  phx-click={JS.push("unarchive", value: %{id: poll.id}) |> hide("##{id}")}
                  class="btn btn-soft btn-success justify-start"
                >
                  <.icon name="hero-archive-box-x-mark" /> Unarchive
                </.button>
              </li>

              <li>
                <.button
                  phx-click={JS.push("delete", value: %{id: poll.id}) |> hide("##{id}")}
                  data-confirm="Are you sure?"
                  class="btn btn-soft btn-error justify-start"
                >
                  <.icon name="hero-trash" /> Delete
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
  def mount(params, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket) do
      Campaigns.subscribe_polls(scope)
    end

    archived = parse_archived_param(params["archived"])
    items = list_polls(scope, archived: archived)

    {:ok,
     socket
     |> assign(:archived, archived)
     |> assign(:page_title, "Polls")
     |> stream(:polls, items)
     |> assign(:count, length(items))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    poll = Campaigns.get_poll!(scope, id)
    {:ok, _} = Campaigns.delete_poll(scope, poll)

    {:noreply, stream_delete(socket, :polls, poll)}
  end

  @impl true
  def handle_event("archive", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    poll = Campaigns.get_poll!(scope, id)
    {:ok, _} = Campaigns.archive_poll(scope, poll)

    {:noreply, stream_delete(socket, :polls, poll)}
  end

  @impl true
  def handle_event("unarchive", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    poll = Campaigns.get_poll!(scope, id)
    {:ok, _} = Campaigns.unarchive_poll(scope, poll)

    {:noreply, stream_delete(socket, :polls, poll)}
  end

  @impl true
  def handle_event("close", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    poll = Campaigns.get_poll!(scope, id)
    {:ok, _} = Campaigns.close_poll(scope, poll)

    {:noreply, stream_delete(socket, :polls, poll)}
  end

  @impl true
  def handle_event("reopen", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    poll = Campaigns.get_poll!(scope, id)
    {:ok, _} = Campaigns.reopen_poll(scope, poll)

    {:noreply, socket}
  end

  @impl true
  def handle_event("duplicate", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    poll = Campaigns.get_poll!(scope, id)
    {:ok, _} = Campaigns.duplicate_poll(scope, poll)

    {:noreply,
     socket
     |> put_flash(:info, "Poll duplicated")}
  end

  @impl true
  def handle_info({type, %Poll{}}, socket)
      when type in [
             :created,
             :updated,
             :deleted,
             :archived,
             :unarchived,
             :closed,
             :reopened,
             :duplicated
           ] do
    current_filter = socket.assigns.archived
    polls = list_polls(socket.assigns.current_scope, archived: current_filter)

    new_filter =
      case {type, Enum.empty?(polls), current_filter} do
        {:archived, true, false} -> :only
        {:unarchived, true, :only} -> false
        {:deleted, true, filter} -> filter
        {:duplicated, true, filter} -> filter
        _ -> current_filter
      end

    final_polls =
      if new_filter == current_filter do
        polls
      else
        list_polls(socket.assigns.current_scope, archived: new_filter)
      end

    {:noreply,
     socket
     |> assign(:archived, new_filter)
     |> stream(:polls, final_polls, reset: true)
     |> assign(:count, length(final_polls))}
  end

  defp list_polls(current_scope, opts) do
    opts = Keyword.put(opts, :preloads, :questions)
    Campaigns.list_polls(current_scope, opts)
  end

  defp parse_archived_param(param) do
    if param in ["only", "true", "false"],
      do: String.to_existing_atom(param),
      else: false
  end

  defp filter_label(true), do: "All"
  defp filter_label(false), do: "Not archived"
  defp filter_label(:only), do: "Archived only"
end
