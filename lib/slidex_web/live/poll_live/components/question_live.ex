defmodule SlidexWeb.PollLive.Components.QuestionLive do
  use SlidexWeb, :live_component

  alias Slidex.{Polling, Search}
  alias SlidexWeb.PollLive.Components.OptionLive

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:results, [])
     |> assign(:show_results, false)
     |> assign(:editing, false)
     |> assign(:body, "")}
  end

  @impl true
  def update(assigns, socket) do
    is_temporary = Map.has_key?(assigns.question, :temp_id)
    body = assigns.question.body || ""
    editing = is_temporary or body == ""

    options = Map.get(assigns.question, :options) || []

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:is_temporary, is_temporary)
     |> assign(:editing, editing)
     |> assign(:body, body)
     |> assign(:options, Map.get(assigns.question, :options, []))
     |> assign(:options, options)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-200 shadow-sm">
      <%= if !@editing do %>
        <!-- VIEW MODE -->
        <div class="card-body p-5">
          <!-- Header -->
          <div class="flex items-center justify-between">
            <!-- Left: Number + Reorder -->
            <div class="flex items-center gap-3">
              <div class="badge badge-neutral badge-soft badge-md">
                {@idx + 1}
              </div>

              <div class="flex items-center gap-0.5">
                <.button
                  type="button"
                  phx-click="reorder"
                  phx-value-direction="higher"
                  phx-target={@myself}
                  class="btn btn-ghost btn-xs"
                  disabled={@idx == 0}
                >
                  <.icon name="hero-chevron-up" class="size-4" />
                </.button>

                <.button
                  type="button"
                  phx-click="reorder"
                  phx-value-direction="lower"
                  phx-target={@myself}
                  class="btn btn-ghost btn-xs"
                  disabled={@idx == @count - 1}
                >
                  <.icon name="hero-chevron-down" class="size-4" />
                </.button>
              </div>
            </div>
            
    <!-- Right: Edit / Delete -->
            <div class="flex items-center gap-2">
              <.button
                type="button"
                phx-click="edit"
                phx-target={@myself}
                class="btn btn-primary btn-soft btn-sm"
              >
                <.icon name="hero-pencil-square" class="size-4" /> Edit
              </.button>

              <.button
                type="button"
                phx-click="delete"
                phx-target={@myself}
                class="btn btn-soft btn-sm btn-error"
              >
                <.icon name="hero-trash" class="size-4" /> Delete
              </.button>
            </div>
          </div>
          
    <!-- Question Body -->
          <div class="mt-3">
            <div class="text-[15px] leading-snug font-medium text-base-content">
              {@body}
            </div>
          </div>
          
    <!-- Options -->
          <div class="mt-5">
            <%= if @options != [] do %>
              <div class="space-y-1.5">
                <%= for {option, idx} <- Enum.with_index(@options) do %>
                  <.live_component
                    module={OptionLive}
                    id={"option-#{option_id(option)}"}
                    option={option}
                    current_scope={@current_scope}
                    question={@question}
                    idx={idx}
                    count={length(@options)}
                  />
                <% end %>
              </div>

              <div class="mt-3 justify-self-end">
                <.add_option_button phx_target={@myself} />
              </div>
            <% else %>
              <!-- Empty State -->
              <div class="rounded border border-dashed border-base-300 bg-base-200/50 px-4 py-5">
                <div class="flex flex-col items-center text-center gap-y-3">
                  <div class="flex flex-row items-center justify-center gap-x-2">
                    <.icon
                      name="hero-chat-bubble-left-right"
                      class="size-8 text-base-content/50"
                    />
                    <p class="text-sm font-semibold text-base-content">No options added yet!</p>
                  </div>

                  <.add_option_button phx_target={@myself} />
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <%= if @editing do %>
        <!-- EDIT MODE -->
        <div class="card-body p-5">
          <.form
            for={to_form(%{"body" => @body})}
            id={"form-#{@id}"}
            phx-change="search"
            phx-target={@myself}
          >
            <!-- Edit Header -->
            <div class="flex items-center justify-between mb-4">
              <div class="badge badge-sm badge-info badge-soft">Editing</div>

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
                  {if @is_temporary, do: "Create", else: "Save changes"}
                </.button>
              </div>
            </div>
            
    <!-- Textarea + Search Results -->
            <div class="space-y-3">
              <.input
                type="textarea"
                name="body"
                value={@body}
                phx-debounce="150"
                autocomplete="off"
                placeholder="Type your question..."
              />

              <%= if @show_results and length(@results) > 0 do %>
                <div class="rounded border border-base-300 bg-base-100 shadow-sm max-h-44 overflow-y-auto text-sm divide-y divide-base-200">
                  <%= for item <- @results do %>
                    <div
                      class="px-4 py-2.5 hover:bg-base-200 cursor-pointer transition-colors"
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
          </.form>
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
        Search.question_body(
          socket.assigns.current_scope,
          search_term,
          limit: 8,
          excluded: [socket.assigns.poll, socket.assigns.question] |> IO.inspect()
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
    send(self(), {:select_question_body, socket.assigns.id, body})

    {:noreply,
     socket
     |> assign(:body, body)
     |> assign(:results, [])
     |> assign(:show_results, false)}
  end

  @impl true
  def handle_event("save", _params, socket) do
    body = String.trim(socket.assigns.body || "")

    cond do
      body == "" ->
        {:noreply, put_flash(socket, :error, "Question body cannot be empty")}

      socket.assigns.is_temporary ->
        case Polling.create_question(socket.assigns.current_scope, socket.assigns.poll, %{
               body: body
             }) do
          {:ok, saved_question} ->
            temp_id = Map.get(socket.assigns.question, :temp_id)
            send(self(), {:question_created, saved_question, temp_id})
            {:noreply, clear_search(socket)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Could not save question")}
        end

      true ->
        case Polling.update_question(socket.assigns.current_scope, socket.assigns.question, %{
               body: body
             }) do
          {:ok, updated_question} ->
            send(self(), {:question_updated, updated_question})
            {:noreply, clear_search(socket)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Could not update question")}
        end
    end
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
     |> assign(:body, socket.assigns.question.body || "")
     |> assign(:results, [])
     |> assign(:show_results, false)}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    if socket.assigns.is_temporary do
      send(self(), {:question_deleted, socket.assigns.question.temp_id})
    else
      Polling.delete_question(socket.assigns.current_scope, socket.assigns.question)
      send(self(), {:question_deleted, socket.assigns.question.id})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("add_option", _params, socket) do
    new_option = %{
      temp_id: "temp_opt_#{System.unique_integer([:positive])}",
      body: "",
      is_correct: false,
      question_id: socket.assigns.question.id || socket.assigns.question[:temp_id],
      editing: true
    }

    send(self(), {:add_temporary_option, socket.assigns.question, new_option})

    {:noreply, socket}
  end

  # Reordering

  @impl true
  def handle_event("reorder", %{"direction" => direction}, socket) do
    direction = String.to_existing_atom(direction)

    Polling.reorder(socket.assigns.current_scope, socket.assigns.question, direction)
    send(self(), {:questions_reordered, socket.assigns.poll})

    {:noreply, socket}
  end

  defp option_id(%{id: id}) when not is_nil(id), do: id
  defp option_id(%{temp_id: temp_id}), do: temp_id
  defp option_id(_), do: Ecto.UUID.generate()

  defp clear_search(socket) do
    socket
    |> assign(:editing, false)
    |> assign(:results, [])
    |> assign(:show_results, false)
  end

  attr :phx_target, :any, required: true
  attr :wide, :boolean, default: false

  def add_option_button(assigns) do
    ~H"""
    <.button
      phx-click="add_option"
      phx-target={@phx_target}
      class={["btn btn-outline btn-primary btn-sm", if(@wide, do: "btn-block btn-soft")]}
    >
      <.icon name="hero-plus" /> Add Option
    </.button>
    """
  end
end
