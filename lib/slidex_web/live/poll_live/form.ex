defmodule SlidexWeb.PollLive.Form do
  use SlidexWeb, :live_view

  alias Slidex.Campaigns
  alias Slidex.Campaigns.Poll

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage poll records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="poll-form" phx-change="validate" phx-submit="save">
        <div class="space-y-6">
          <.input field={@form[:title]} type="text" label="Title" required />

          <div
            class="tooltip"
            data-tip="Public polls are accessible to guest users who haven't logged on to Slidex"
          >
            <.input field={@form[:is_public]} type="checkbox" label="Public poll" />
          </div>

          <div>
            <p class="text-neutral text-xs border border-dashed border-base-300 bg-base-200 rounded p-3">
              You can generate an access code that will be required for participating in the voting process, regardless of whether the poll is public or not.
            </p>
            <.input field={@form[:access_code]} type="text" label="Access code" />
          </div>

          <div>
            <p class="text-neutral text-xs border border-dashed border-base-300 bg-base-200 rounded p-3">
              If you set an expiration date and time, participation in the voting process will be blocked after that moment in time.
            </p>
            <.input field={@form[:expires_at]} type="datetime-local" label="Expires at" />
          </div>
        </div>

        <footer class="mt-12 flex flex-row justify-between items-center">
          <.button navigate={return_path(@current_scope, @return_to, @poll)}>
            <.icon name="hero-arrow-left" class="size-5" /> Cancel
          </.button>
          <.button phx-disable-with="Saving..." variant="primary">
            <.icon name="hero-check-circle" class="size-5" /> Save
          </.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    poll = Campaigns.get_poll!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, "Edit Poll")
    |> assign(:poll, poll)
    |> assign(:form, to_form(Campaigns.change_poll(socket.assigns.current_scope, poll)))
  end

  defp apply_action(socket, :new, _params) do
    poll = %Poll{user_id: socket.assigns.current_scope.user.id}

    socket
    |> assign(:page_title, "New Poll")
    |> assign(:poll, poll)
    |> assign(:form, to_form(Campaigns.change_poll(socket.assigns.current_scope, poll)))
  end

  @impl true
  def handle_event("validate", %{"poll" => poll_params}, socket) do
    changeset =
      Campaigns.change_poll(socket.assigns.current_scope, socket.assigns.poll, poll_params)

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"poll" => poll_params}, socket) do
    save_poll(socket, socket.assigns.live_action, poll_params)
  end

  defp save_poll(socket, :edit, poll_params) do
    case Campaigns.update_poll(socket.assigns.current_scope, socket.assigns.poll, poll_params) do
      {:ok, poll} ->
        {:noreply,
         socket
         |> put_flash(:info, "Poll updated successfully")
         |> push_navigate(
           to: return_path(socket.assigns.current_scope, socket.assigns.return_to, poll)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_poll(socket, :new, poll_params) do
    case Campaigns.create_poll(socket.assigns.current_scope, poll_params) do
      {:ok, poll} ->
        {:noreply,
         socket
         |> put_flash(:info, "Poll created successfully")
         |> push_navigate(
           to: return_path(socket.assigns.current_scope, socket.assigns.return_to, poll)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path(_scope, "index", _poll), do: ~p"/polls"
  defp return_path(_scope, "show", poll), do: ~p"/polls/#{poll}"
end
