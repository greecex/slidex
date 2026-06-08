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
        <:actions>
          <.button :if={@live_action == :edit} navigate={~p"/polls/#{@poll}/questions"}>
            <.icon name="hero-question-mark-circle" />
            <span class="hidden md:block">Edit Questions</span>
          </.button>
        </:actions>
      </.header>

      <.form for={@form} id="poll-form" phx-change="validate" phx-submit="save">
        <div class="space-y-6">
          <div>
            <.input field={@form[:title]} type="text" label="Title" required />
            <.input field={@form[:description]} type="textarea" label="Description (optional)" />
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
         |> push_navigate(to: return_path(socket.assigns.current_scope, "questions", poll))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path(_scope, "index", _poll), do: ~p"/polls"
  defp return_path(_scope, "show", poll), do: ~p"/polls/#{poll}"
  defp return_path(_scope, "questions", poll), do: ~p"/polls/#{poll}/questions"
end
