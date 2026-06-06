defmodule SlidexWeb.PollLive.Components.QuestionLiveComponent do
  use SlidexWeb, :live_component

  alias Slidex.Polling

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:results, [])
     |> assign(:show_results, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.input
        id={"question-body-#{@id}"}
        name="question[body]"
        value={@question.body}
        label="Question body"
        phx-change="search"
        phx-target={@myself}
        phx-debounce="300"
        autocomplete="off"
      />

      <%= if @show_results and length(@results) > 0 do %>
        <div class="absolute z-50 mt-1 w-full border border-base-300 bg-base-100 rounded-xl shadow-sm max-h-60 overflow-auto divide-y divide-base-200 text-sm">
          <%= for item <- @results do %>
            <div
              class="px-3 py-2 hover:bg-base-200 cursor-pointer"
              phx-click="select"
              phx-value-body={item.body}
              phx-target={@myself}
            >
              <span class="truncate">{item.body}</span>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("search", %{"value" => value}, socket) do
    search_term = String.trim(value || "")

    results =
      if String.length(search_term) > 2 do
        Polling.search_question_bodies(
          socket.assigns.current_scope,
          search_term,
          limit: 8
        )
      else
        []
      end

    {:noreply,
     socket
     |> assign(:results, results)
     |> assign(:show_results, length(results) > 0)}
  end

  @impl true
  def handle_event("select", %{"body" => body}, socket) do
    # Send the selected body to the parent LiveView
    send(self(), {:select_question_body, socket.assigns.id, body})

    {:noreply,
     socket
     |> assign(:results, [])
     |> assign(:show_results, false)}
  end
end
