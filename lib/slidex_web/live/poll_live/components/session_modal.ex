defmodule SlidexWeb.PollLive.Components.SessionModal do
  use SlidexWeb, :live_component

  alias Phoenix.LiveView.JS
  alias Slidex.Voting

  import SlidexWeb.Components.Modals

  @impl true
  def update(assigns, socket) do
    changeset =
      Voting.change_session(
        assigns.current_scope,
        %Slidex.Voting.Session{}
      )

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("validate", %{"session" => params}, socket) do
    changeset =
      Voting.change_session(
        socket.assigns.current_scope,
        %Slidex.Voting.Session{},
        params
      )
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"session" => params}, socket) do
    params =
      Map.put(params, "is_survey", socket.assigns.is_survey)

    case Voting.create_session(
           socket.assigns.current_scope,
           socket.assigns.poll,
           params
         ) do
      {:ok, session} ->
        send(self(), {:session_created, session})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("close", _params, socket) do
    send(self(), {:close_modal})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.modal
        id={@id}
        show={@show}
        closeable={true}
        on_cancel={JS.push("close", target: @myself)}
      >
        <:title>
          Create a new {if @is_survey, do: "survey", else: "voting session"}
        </:title>

        <.form
          for={@form}
          id={"new-session-form-#{@id}"}
          phx-target={@myself}
          phx-change="validate"
          phx-submit="save"
        >
          <.input field={@form[:title]} type="text" label="Title" required />
          <.input field={@form[:description]} type="textarea" label="Description (optional)" />

          <div class="modal-action">
            <button
              type="button"
              class="btn btn-ghost"
              phx-click={JS.push("close", target: @myself)}
            >
              Cancel
            </button>

            <.button type="submit" class="btn btn-primary">
              Create {if @is_survey, do: "Survey", else: "Voting Session"}
            </.button>
          </div>
        </.form>
      </.modal>
    </div>
    """
  end
end
