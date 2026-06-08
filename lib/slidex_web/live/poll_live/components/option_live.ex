defmodule SlidexWeb.PollLive.Components.OptionLive do
  use SlidexWeb, :live_component

  alias Slidex.{Polling, Search}

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:editing, false)
     |> assign(:body, "")
     |> assign(:is_correct, false)
     |> assign(:results, [])
     |> assign(:show_results, false)}
  end

  @impl true
  def update(assigns, socket) do
    option = assigns.option
    is_temporary = Map.has_key?(option, :temp_id)

    socket =
      socket
      |> assign(assigns)
      |> assign(:is_temporary, is_temporary)
      |> assign(:option, option)

    should_edit = socket.assigns.editing or (is_temporary and (option.body || "") == "")

    socket =
      if should_edit do
        socket
      else
        socket
        |> assign(:body, option.body || "")
        |> assign(:is_correct, option.is_correct || false)
      end

    {:ok, assign(socket, :editing, should_edit)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={[
      "flex items-start gap-3 rounded p-3 transition-colors",
      if(@is_correct,
        do: "bg-success/10 border border-success/20",
        else: "border border-base-200 bg-base-100"
      )
    ]}>
      <%= if @editing do %>
        <!-- EDIT MODE -->
        <.form
          for={to_form(%{"body" => @body})}
          id={"form-#{@id}"}
          phx-change="search"
          phx-target={@myself}
          class="w-full"
        >
          <!-- Edit Header -->
          <div class="flex items-center justify-between mb-3">
            <div class="badge badge-info badge-soft badge-sm">Editing</div>

            <div class="flex items-center gap-2">
              <.button
                type="button"
                phx-click={if String.trim(@body) == "", do: "delete", else: "cancel_edit"}
                phx-target={@myself}
                class="btn btn-ghost btn-sm"
              >
                <.icon name="hero-x-mark" class="size-4" /> Cancel
              </.button>

              <.button
                type="button"
                phx-click="save"
                phx-target={@myself}
                disabled={String.trim(@body || "") == ""}
                class="btn btn-success btn-sm"
              >
                <.icon name="hero-check" class="size-4" />
                {if @is_temporary, do: "Create", else: "Save"}
              </.button>
            </div>
          </div>

          <div class="flex gap-3">
            <!-- Body Input -->
            <div class="flex-1">
              <.input
                name="body"
                value={@body}
                phx-debounce="150"
                autocomplete="off"
                placeholder="Type an option..."
              />
              
    <!-- Search Results -->
              <%= if @show_results and length(@results) > 0 do %>
                <div class="mt-2 rounded border border-base-300 bg-base-100 shadow-sm max-h-40 overflow-y-auto text-sm divide-y divide-base-200">
                  <%= for item <- @results do %>
                    <div
                      class="px-4 py-2 hover:bg-base-200 cursor-pointer transition-colors"
                      phx-click="select"
                      phx-value-body={item}
                      phx-target={@myself}
                    >
                      {item}
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
            
    <!-- Correct Toggle -->
            <div class="flex flex-col items-center pt-2">
              <label class="flex flex-row items-center gap-1 cursor-pointer">
                <div class="text-xs font-medium text-base-content/70">Correct</div>
                <.input
                  type="checkbox"
                  name="is_correct"
                  checked={@is_correct}
                  phx-click="toggle_correct"
                  phx-target={@myself}
                  class="toggle toggle-success toggle-sm"
                />
              </label>
            </div>
          </div>
        </.form>
      <% end %>

      <%= if !@editing do %>
        <!-- VIEW MODE -->
        <div class="flex items-start gap-3 w-full">
          <!-- Number -->
          <div class="badge badge-neutral badge-soft badge-md mt-0.5">
            {@idx + 1}
          </div>
          
    <!-- Reorder -->
          <div class="flex flex-col sm:flex-row gap-0.5 pt-0.5">
            <.button
              type="button"
              phx-click="reorder"
              phx-value-direction="higher"
              phx-target={@myself}
              class="btn btn-ghost btn-xs"
              disabled={@idx == 0}
            >
              <.icon name="hero-chevron-up" class="size-3.5" />
            </.button>

            <.button
              type="button"
              phx-click="reorder"
              phx-value-direction="lower"
              phx-target={@myself}
              class="btn btn-ghost btn-xs"
              disabled={@idx == @count - 1}
            >
              <.icon name="hero-chevron-down" class="size-3.5" />
            </.button>
          </div>
          
    <!-- Body + Correct Indicator -->
          <div class="flex-1 min-w-0 pt-0.5">
            <div class="flex items-start gap-2">
              <%= if @is_correct do %>
                <div class="tooltip tooltip-right" data-tip="This is a correct option">
                  <.icon name="hero-check-badge" class="size-5 text-success mt-0.5 flex-shrink-0" />
                </div>
              <% end %>
              <p class="text-sm leading-snug text-base-content break-words font-semibold">
                {@body}
              </p>
            </div>
          </div>
          
    <!-- Actions -->
          <div class="flex items-center gap-1 flex-shrink-0">
            <.button
              type="button"
              phx-click="edit"
              phx-target={@myself}
              class="btn btn-primary btn-soft btn-xs"
            >
              <.icon name="hero-pencil-square" class="size-3.5" /> Edit
            </.button>

            <.button
              type="button"
              phx-click="delete"
              phx-target={@myself}
              class="btn btn-error btn-soft btn-xs"
            >
              <.icon name="hero-trash" class="size-3.5" /> Delete
            </.button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("search", %{"body" => value}, socket) do
    search_term = String.trim(value)

    results =
      if String.length(search_term) > 2 do
        Search.option_body(
          socket.assigns.current_scope,
          search_term,
          limit: 8,
          excluded: [socket.assigns.question, socket.assigns.option] |> IO.inspect()
        )
      else
        []
      end

    {:noreply,
     socket
     |> assign(:body, search_term)
     |> assign(:results, results)
     |> assign(:show_results, length(results) > 0)}
  end

  @impl true
  def handle_event("select", %{"body" => body}, socket) do
    send(self(), {:select_option_body, socket.assigns.id, body})

    {:noreply,
     socket
     |> assign(:body, body)
     |> assign(:results, [])
     |> assign(:show_results, false)}
  end

  @impl true
  def handle_event("toggle_correct", _params, socket) do
    {:noreply, assign(socket, :is_correct, !socket.assigns.is_correct)}
  end

  @impl true
  def handle_event("edit", _params, socket) do
    {:noreply, assign(socket, :editing, true)}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing, false)
     |> assign(:body, socket.assigns.option.body || "")
     |> assign(:is_correct, socket.assigns.option.is_correct || false)}
  end

  @impl true
  def handle_event("save", _params, socket) do
    scope = socket.assigns.current_scope
    option = socket.assigns.option
    body = String.trim(socket.assigns.body || "")

    if body == "" do
      {:noreply, put_flash(socket, :error, "Option body cannot be empty")}
    else
      attrs = %{body: body, is_correct: socket.assigns.is_correct}

      if socket.assigns.is_temporary do
        question = socket.assigns.question

        case Polling.create_option(scope, question, attrs) do
          {:ok, persisted_option} ->
            send(self(), {:option_created, persisted_option, temp_id: option.temp_id})
            {:noreply, assign(socket, :editing, false)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Could not save option")}
        end
      else
        case Polling.update_option(scope, option, attrs) do
          {:ok, updated_option} ->
            send(self(), {:option_updated, updated_option})
            {:noreply, assign(socket, :editing, false)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Could not update option")}
        end
      end
    end
  end

  @impl true
  def handle_event("delete", _params, socket) do
    if socket.assigns.is_temporary do
      send(self(), {:option_deleted, socket.assigns.option.temp_id})
      {:noreply, socket}
    else
      Polling.delete_option(socket.assigns.current_scope, socket.assigns.option)
      send(self(), {:option_deleted, socket.assigns.option.id})
      {:noreply, assign(socket, :editing, false)}
    end
  end

  # Reordering

  @impl true
  def handle_event("reorder", %{"direction" => direction}, socket) do
    direction = String.to_existing_atom(direction)

    Polling.reorder(socket.assigns.current_scope, socket.assigns.option, direction)
    send(self(), {:options_reordered, socket.assigns.question})

    {:noreply, socket}
  end
end
