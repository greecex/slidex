defmodule SlidexWeb.PollLive.Index do
  use SlidexWeb, :live_view

  alias Slidex.Campaigns
  alias Slidex.Campaigns.Poll

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

      <div class="space-y-2">
        <%= for {id, poll} <- @streams.polls do %>
          <div class={[
            "flex justify-between gap-x-4 rounded-lg border border-base-300 bg-base-100 p-3 ps-4 group  transition-all",
            if(poll.description, do: "items-start", else: "items-center`")
          ]}>
            <div class="min-w-0 flex-1">
              <div class="font-medium truncate">
                <.link navigate={~p"/polls/#{poll}"} class="group-hover:text-primary">
                  {poll.title}
                </.link>
              </div>

              <div :if={poll.description} class="text-xs text-base-content/60">
                {poll.description}
              </div>

              <div class="flex flex-row items-center justify-start gap-x-2">
                <div :if={poll.archived_at} class="badge badge-warning badge-soft badge-sm">
                  <.icon name="hero-archive-box" /> <span class="hidden md:block">Archived</span>
                </div>
                <div
                  :if={poll.questions == []}
                  class="tooltip tooltip-sm tooltip-right"
                  data-tip="No questions defined"
                >
                  <.icon name="hero-exclamation-triangle" class="size-5 text-warning" />
                </div>
              </div>
            </div>

            <div class="flex items-center gap-x-2">
              <div class="dropdown dropdown-bottom dropdown-end">
                <div tabindex="0" role="button" class="btn btn-ghost p-1">
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
            </div>
          </div>
        <% end %>
      </div>
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

  @impl true
  # Global "app:visitors" presence_diff broadcasts (see PollLive.Show for explanation).
  # Index page does not display the global visitor UI.
  def handle_info(%{topic: "app:visitors", event: "presence_diff"}, socket) do
    {:noreply, socket}
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

  # The global VisitorIdentity hook (in Layouts.app) fires this on every LV.
  # Tracking is handled centrally in GlobalPresence on_mount attach_hook.
  def handle_event("visitor-identified", _params, socket) do
    {:noreply, socket}
  end
end
