defmodule SlidexWeb.PollLive.Components.OptionLive do
  use SlidexWeb, :live_component

  alias Slidex.Polling

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:editing, false)
     |> assign(:body, "")
     |> assign(:is_correct, false)}
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

    # Only sync from parent when not editing
    socket =
      if socket.assigns.editing do
        socket
      else
        socket
        |> assign(:body, option.body || "")
        |> assign(:is_correct, option.is_correct || false)
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex items-center gap-2 bg-base-100 border border-base-300 rounded px-3 py-2">
      <%= if @editing do %>
        <div class="flex-1 flex items-center gap-2">
          <input
            type="text"
            value={@body}
            phx-change="update_body"
            phx-target={@myself}
            class="input input-bordered input-sm flex-1"
          />
          <label class="flex items-center gap-1 text-sm">
            <input
              type="checkbox"
              checked={@is_correct}
              phx-click="toggle_correct"
              phx-target={@myself}
            /> Correct
          </label>
        </div>

        <button type="button" phx-click="save" phx-target={@myself} class="btn btn-primary btn-sm">
          Save
        </button>
        <button
          type="button"
          phx-click="cancel_edit"
          phx-target={@myself}
          class="btn btn-ghost btn-sm"
        >
          Cancel
        </button>
      <% else %>
        <div class="flex-1">
          {@body}
          <%= if @is_correct do %>
            <span class="badge badge-success badge-sm ml-2">Correct</span>
          <% end %>
        </div>

        <button type="button" phx-click="edit" phx-target={@myself} class="btn btn-ghost btn-sm">
          Edit
        </button>
        <button
          type="button"
          phx-click="delete"
          phx-target={@myself}
          class="btn btn-error btn-soft btn-sm"
        >
          Delete
        </button>
      <% end %>
    </div>
    """
  end

  # === Events ===

  @impl true
  def handle_event("update_body", %{"value" => value}, socket) do
    {:noreply, assign(socket, :body, value)}
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
        # For now we just notify parent — persistence logic comes later
        new_option = Map.merge(option, attrs)
        send(self(), {:option_created, new_option})
        {:noreply, assign(socket, :editing, false)}
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
    else
      Polling.delete_option(socket.assigns.current_scope, socket.assigns.option)
      send(self(), {:option_deleted, socket.assigns.option.id})
    end

    {:noreply, socket}
  end
end
