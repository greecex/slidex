defmodule SlidexWeb.PollLive.Components.QuestionLive do
  use SlidexWeb, :live_component

  alias Slidex.Polling
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
    <div class="card bg-base border border-base-200 p-3 shadow">
      <%= if !@editing do %>
        <div class="w-full flex flex-row justify-between items-center">
          <.button
            type="button"
            phx-click="delete"
            class="btn btn-soft btn-sm btn-error"
            phx-target={@myself}
          >
            <.icon name="hero-trash" /> Delete
          </.button>
          <.button
            type="button"
            phx-click="edit"
            phx-target={@myself}
            class="btn btn-primary btn-soft btn-sm"
          >
            <.icon name="hero-pencil-square" /> Edit
          </.button>
        </div>

        <div class="divider divider-y my-1 divider-base-200" />

        <div class="card rounded-sm w-full font-semibold px-1 py-2 leading-tight">
          {@body}
        </div>

        <div class="mt-3">
          <%= if @options != [] do %>
            <div class="space-y-2">
              <%= for option <- @options do %>
                <.live_component
                  module={OptionLive}
                  id={"option-#{option_id(option)}"}
                  option={option}
                  current_scope={@current_scope}
                  question={@question}
                />
              <% end %>
              <div class="mt-3">
                <.add_option_button phx_target={@myself} wide />
              </div>
            </div>
          <% else %>
            <div class="card w-full bg-base-100 shadow border border-dashed border-base-300">
              <div class="card-body items-center py-4">
                <.icon name="hero-face-frown" class="size-8 text-neutral" />
                <div class="text-sm">No options yet</div>
                <.add_option_button phx_target={@myself} />
              </div>
            </div>
          <% end %>
        </div>
      <% end %>

      <%= if @editing do %>
        <.form
          for={to_form(%{"body" => @body})}
          id={"form-#{@id}"}
          phx-change="search"
          phx-target={@myself}
        >
          <div class="w-full flex flex-row justify-between items-center">
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
              class="btn btn-success btn-sm"
            >
              <.icon name="hero-check" />
              <span class="hidden md:block">{if @is_temporary, do: "Save", else: "Update"}</span>
            </.button>
          </div>

          <div class="divider divider-y my-1 divider-base-200" />

          <div class="space-y-2">
            <.input
              type="textarea"
              name="body"
              value={@body}
              phx-debounce="150"
              autocomplete="off"
              placeholder="Type your question..."
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
        </.form>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("search", %{"body" => value}, socket) do
    search_term = String.trim(value)

    results =
      if String.length(search_term) > 2 do
        Polling.search_question_bodies(
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
      class={["btn btn-primary btn-soft btn-sm", if(@wide, do: "btn-block btn-soft")]}
    >
      <.icon name="hero-plus" /> Add Option
    </.button>
    """
  end
end
