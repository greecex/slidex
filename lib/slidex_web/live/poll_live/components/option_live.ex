defmodule SlidexWeb.PollLive.Components.OptionLive do
  use SlidexWeb, :live_component

  alias Slidex.Polling

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
      "flex items-start gap-3 rounded p-2",
      if(@is_correct,
        do: "bg-success/10 border border-success/20",
        else: "border border-base-200"
      )
    ]}>
      <%= if @editing do %>
        <.form
          for={to_form(%{"body" => @body})}
          id={"form-#{@id}"}
          phx-change="search"
          phx-target={@myself}
          class="w-full"
        >
          <div class="flex-1 flex items-center gap-2">
            <div class="space-y-2 w-full">
              <.input
                name="body"
                value={@body}
                phx-debounce="150"
                autocomplete="off"
                placeholder="Type an option..."
              />

              <%= if @show_results and length(@results) > 0 do %>
                <div class="border border-base-300 bg-base-100 rounded mt-0 max-h-48 overflow-y-auto text-sm divide-y divide-base-200">
                  <%= for item <- @results do %>
                    <div
                      class="px-3 py-2 bg-base-100 hover:bg-base-200 cursor-pointer hover:text-primary"
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

            <label class="flex items-center gap-1 text-xs font-semibold cursor-pointer">
              <.input
                type="checkbox"
                name="is_correct"
                checked={@is_correct}
                phx-click="toggle_correct"
                phx-target={@myself}
                class="toggle toggle-success toggle-lg"
              /> Correct
            </label>
          </div>

          <div class="flex flex-row gap-x-1 items-center justify-between w-full mt-1">
            <.button
              type="button"
              phx-click={if String.trim(@body) == "", do: "delete", else: "cancel_edit"}
              phx-target={@myself}
              class="btn btn-soft btn-sm"
            >
              <.icon name="hero-x-mark" /> <span class="hidden md:block">Cancel</span>
            </.button>

            <.button
              type="button"
              phx-click="save"
              phx-target={@myself}
              disabled={String.trim(@body || "") == ""}
              class="btn btn-info btn-sm"
            >
              <.icon name="hero-check" />
              <span class="hidden md:block">{if @is_temporary, do: "Save", else: "Update"}</span>
            </.button>
          </div>
        </.form>
      <% end %>

      <%= if !@editing do %>
        <div class="flex-1">
          <div class="flex flex-row gap-x-0">
            <%= if @is_correct do %>
              <div class="tooltip" data-tip="This is a correct option">
                <.icon name="hero-check-badge" class="text-success" />
              </div>
            <% end %>
            <p class="leading-tight text-sm mt-1 ps-1">{@body}</p>
          </div>
        </div>

        <div class="flex flex-col lg:flex-row gap-1">
          <.button
            type="button"
            phx-click="edit"
            phx-target={@myself}
            class="btn btn-primary btn-soft btn-sm"
          >
            <.icon name="hero-pencil-square" /> <span class="hidden md:block">Edit</span>
          </.button>
          <.button
            type="button"
            phx-click="delete"
            phx-target={@myself}
            class="btn btn-error btn-soft btn-sm"
          >
            <.icon name="hero-trash" /> <span class="hidden md:block">Delete</span>
          </.button>
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
        Polling.search_option_bodies(
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
end
