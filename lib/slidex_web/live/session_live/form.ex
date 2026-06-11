defmodule SlidexWeb.SessionLive.Form do
  use SlidexWeb, :live_view

  alias Slidex.{Campaigns, Voting}
  alias Slidex.Voting.Session
  alias Slidex.Campaigns.Poll

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
        <:subtitle>Create or edit a voting or survey session.</:subtitle>
      </.header>

      <.form for={@form} id="session-form" phx-change="validate" phx-submit="save">
        <div class="space-y-6">
          <!-- Poll Selector -->
          <%= if @live_action == :new and @poll_options do %>
            <.input
              field={@form[:poll_id]}
              type="select"
              label="Poll"
              options={@poll_options}
              prompt="Select a poll"
              required
            />

            <%= if @poll && @poll.description do %>
              <div class="flex flex-row gap-x-2 w-full">
                <p class="flex-1 text-sm text-base-content/90 border-l-4 border-base-300 p-2 ps-3">
                  {@poll.description}
                </p>
                <div
                  class="tooltip tooltip-left"
                  data-tip="Show this description to users too?"
                >
                  <.input
                    field={@form[:show_poll_description]}
                    type="checkbox"
                    label="Show to viewers"
                    class="toggle toggle-primary"
                  />
                </div>
              </div>
            <% end %>
          <% else %>
            <%= if @poll do %>
              <div>
                <div class="text-sm font-medium text-base-content/70">Poll</div>
                <div class="font-semibold">{@poll.title}</div>
                <%= if @poll.description do %>
                  <div class="text-sm text-base-content/80 mt-1">
                    {@poll.description}
                  </div>
                <% end %>
              </div>
            <% end %>
          <% end %>
          
    <!-- Kind Selector -->
          <div :if={@live_action == :new} class="fieldset">
            <label>
              <span class="label mb-1">Kind</span>
              <div class="join w-full">
                <label class={[
                  "join-item btn flex-1",
                  if(@kind == "voting", do: "btn-primary", else: "btn-soft")
                ]}>
                  <input
                    type="radio"
                    name="kind"
                    value="voting"
                    class="hidden"
                    checked={@kind == "voting"}
                    phx-click="set_kind"
                    phx-value-kind="voting"
                  />
                  <.icon name="hero-chart-bar" class="size-5 mr-2" /> Voting
                </label>

                <label class={[
                  "join-item btn flex-1",
                  if(@kind == "survey", do: "btn-primary", else: "btn-soft")
                ]}>
                  <input
                    type="radio"
                    name="kind"
                    value="survey"
                    class="hidden"
                    checked={@kind == "survey"}
                    phx-click="set_kind"
                    phx-value-kind="survey"
                  />
                  <.icon name="hero-clipboard-document-list" class="size-5 mr-2" /> Survey
                </label>
              </div>
            </label>
          </div>

          <div>
            <.input field={@form[:title]} type="text" label="Title" required />
            <.input field={@form[:description]} type="textarea" label="Description (optional)" />
          </div>

          <div
            class="tooltip tooltip-right"
            data-tip="Accessible to guest users who haven't logged on?"
          >
            <.input
              field={@form[:is_public]}
              type="checkbox"
              label="Public"
              class="toggle toggle-primary"
            />
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div>
              <h3 class="font-semibold mb-2">
                Access code <span class="font-light text-info text-xs">(optional)</span>
                <span class="badge badge-ghost badge-sm align-middle">Not enforced yet</span>
              </h3>
              <p class="text-neutral text-xs border border-dashed border-base-300 bg-base-200 rounded p-3">
                Saved with the session for an upcoming release. Joining does not require it yet.
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

        <footer class="mt-12 flex flex-row justify-between items-center">
          <.button navigate={poll_return_path(@poll, @session)}>
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
    kind =
      case params["kind"] do
        "survey" -> "survey"
        _ -> "voting"
      end

    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> assign(:kind, kind)
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "show"

  defp apply_action(socket, :edit, %{"id" => id}) do
    session = Voting.get_session!(socket.assigns.current_scope, id)
    poll = Campaigns.get_poll!(socket.assigns.current_scope, session.poll_id)

    kind = if session.state == :survey, do: "survey", else: "voting"

    socket
    |> assign(:page_title, "Edit Session")
    |> assign(:kind, kind)
    |> assign(:poll, poll)
    |> assign(:session, session)
    |> assign(:form, to_form(Voting.change_session(socket.assigns.current_scope, session, %{})))
  end

  defp apply_action(socket, :new, params) do
    scope = socket.assigns.current_scope
    kind = socket.assigns.kind

    poll =
      with poll_id when is_binary(poll_id) <- params["poll"],
           %Poll{} = p <- Campaigns.get_poll(scope, poll_id),
           do: p

    poll_options =
      if is_nil(poll) do
        scope
        |> Campaigns.list_polls()
        |> Enum.map(&{&1.title, &1.id})
      end

    session = %Session{
      poll_id: if(is_nil(poll), do: nil, else: poll.id),
      state: if(kind == "survey", do: :survey, else: :pending)
    }

    socket
    |> assign(:page_title, "New Session")
    |> assign(:poll, poll)
    |> assign(:poll_options, poll_options)
    |> assign(:session, session)
    |> assign(:form, to_form(Voting.change_session(socket.assigns.current_scope, session, %{})))
  end

  @impl true
  def handle_event("validate", %{"session" => session_params}, socket) do
    socket = maybe_assign_selected_poll(socket, session_params["poll_id"])

    changeset =
      Voting.change_session(socket.assigns.current_scope, socket.assigns.session, session_params)

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"session" => session_params}, socket) do
    save_session(socket, socket.assigns.live_action, session_params)
  end

  def handle_event("set_kind", %{"kind" => kind}, socket) when kind in ["voting", "survey"] do
    socket =
      socket
      |> assign(:kind, kind)
      |> update_session_state(kind)

    {:noreply, socket}
  end

  def handle_event("generate_code", _params, socket) do
    current_params = socket.assigns.form.params || %{}
    new_params = Map.put(current_params, "access_code", Slidex.Voting.AccessCode.generate())

    changeset =
      Voting.change_session(socket.assigns.current_scope, socket.assigns.session, new_params)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("clear_code", _params, socket) do
    current_params = socket.assigns.form.params || %{}
    new_params = Map.put(current_params, "access_code", nil)

    changeset =
      Voting.change_session(socket.assigns.current_scope, socket.assigns.session, new_params)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  defp maybe_assign_selected_poll(socket, nil), do: socket

  defp maybe_assign_selected_poll(socket, poll_id) do
    current = socket.assigns.poll

    if current && current.id == poll_id do
      socket
    else
      poll = Campaigns.get_poll!(socket.assigns.current_scope, poll_id)
      assign(socket, :poll, poll)
    end
  end

  defp update_session_state(socket, kind) do
    new_state = if kind == "survey", do: :survey, else: :pending

    updated_session = %{socket.assigns.session | state: new_state}

    assign(socket,
      session: updated_session,
      form: to_form(Voting.change_session(socket.assigns.current_scope, updated_session, %{}))
    )
  end

  defp save_session(socket, :edit, session_params) do
    poll_id = socket.assigns.session.poll_id

    state = if socket.assigns.kind == "survey", do: :survey, else: :pending

    params =
      session_params
      |> Map.put("state", state)
      |> Map.put("access_code", socket.assigns.form[:access_code].value)

    case Voting.update_session(
           socket.assigns.current_scope,
           socket.assigns.session,
           params
         ) do
      {:ok, _session} ->
        {:noreply,
         socket
         |> put_flash(:info, "Session updated successfully")
         |> push_navigate(to: ~p"/polls/#{poll_id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_session(socket, :new, session_params) do
    scope = socket.assigns.current_scope

    poll =
      cond do
        socket.assigns.poll -> socket.assigns.poll
        poll_id = session_params["poll_id"] -> Campaigns.get_poll!(scope, poll_id)
        true -> nil
      end

    state = if socket.assigns.kind == "survey", do: :survey, else: :pending

    params =
      session_params
      |> Map.put("state", state)
      |> Map.put("access_code", socket.assigns.form[:access_code].value)

    case Voting.create_session(scope, poll, params) do
      {:ok, session} ->
        {:noreply,
         socket
         |> put_flash(:info, "Session created successfully")
         |> push_navigate(to: ~p"/polls/#{session.poll_id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  # Cancel button always returns to the Poll Show page
  defp poll_return_path(poll, _session) when not is_nil(poll) do
    ~p"/polls/#{poll.id}"
  end

  defp poll_return_path(_poll, session)
       when not is_nil(session) and not is_nil(session.poll_id) do
    ~p"/polls/#{session.poll_id}"
  end

  defp poll_return_path(_poll, _session), do: ~p"/polls"
end
