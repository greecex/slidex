defmodule SlidexWeb.PollLive.Components.SessionModal do
  @moduledoc """
  LiveComponent for the modal that creates and edits a poll's voting session.
  """
  use SlidexWeb, :live_component

  alias Phoenix.LiveView.JS
  alias Slidex.Voting
  alias Slidex.Voting.Session

  import SlidexWeb.Components.Modals

  @impl true
  def update(assigns, socket) do
    changeset =
      Voting.change_session(
        assigns.current_scope,
        %Session{}
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
        %Session{},
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
          <div class="space-y-6">
            <div>
              <.input field={@form[:title]} type="text" label="Title" required />
              <.input field={@form[:description]} type="textarea" label="Description (optional)" />
            </div>

            <div
              class="tooltip tooltip-right"
              data-tip="Will this be accessible to guests who haven't logged?"
            >
              <.input field={@form[:is_public]} type="checkbox" label="Public" />
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div>
                <h3 class="font-semibold mb-2">
                  Access code <span class="font-light text-info text-xs">(optional)</span>
                </h3>
                <p class="text-neutral text-xs border border-dashed border-base-300 bg-base-200 rounded p-3">
                  You can generate an access code that will be required for participating in the voting or survey process, regardless of whether it's is public .
                </p>
                <.button
                  :if={!@form[:access_code].value}
                  type="button"
                  phx-click="generate_code"
                  class="btn btn-block btn-soft btn-primary mt-1"
                >
                  <.icon name="hero-lock-closed" /> Generate code
                </.button>

                <div
                  :if={@form[:access_code].value}
                  class="w-full flex flex-row gap-x-1 items-center mt-1"
                >
                  <div class="font-semibold text-center flex-1 border border-base-200 rounded py-1 px-2">
                    {@form[:access_code].value}
                  </div>
                  <.button
                    type="button"
                    phx-click="clear_code"
                    class="btn btn-soft btn-error"
                  >
                    <.icon name="hero-lock-open" /> Remove code
                  </.button>
                </div>
              </div>

              <div>
                <h3 class="font-semibold mb-2">
                  Expiration <span class="font-light text-info text-xs">(optional)</span>
                </h3>
                <p class="text-neutral text-xs border border-dashed border-base-300 bg-base-200 rounded p-3">
                  If you set an expiration date and time, participation in the voting process will be blocked after that moment in time.
                </p>
                <.input field={@form[:expires_at]} type="datetime-local" />
              </div>
            </div>
          </div>

          <div class="modal-action w-full flex flex-row items-center justify-between mt-12">
            <.button
              type="button"
              class="btn btn-ghost"
              phx-click={JS.push("close", target: @myself)}
            >
              <.icon name="hero-x-mark" /> Cancel
            </.button>

            <.button type="submit" class="btn btn-primary">
              <.icon name="hero-check" /> Save
            </.button>
          </div>
        </.form>
      </.modal>
    </div>
    """
  end
end
