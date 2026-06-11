defmodule SlidexWeb.PollLive.Questions do
  use SlidexWeb, :live_view

  alias Slidex.{Campaigns, Polling, Preloader}
  alias SlidexWeb.PollLive.Components.QuestionLive

  @impl true
  def mount(%{"id" => poll_id}, _session, socket) do
    poll =
      socket.assigns.current_scope
      |> Campaigns.get_poll!(poll_id)
      |> Preloader.with_preloads()

    {:ok,
     socket
     |> assign(:poll, poll)
     |> assign(:questions, poll.questions)
     |> assign(:page_title, "Edit Questions")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@poll.title}
        <:subtitle>Manage Questions</:subtitle>
        <:actions>
          <.button navigate={~p"/polls/#{@poll}"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.add_question_button :if={@questions != []} />
        </:actions>
      </.header>

      <div class="mt-8 space-y-8">
        <%= if @questions != [] do %>
          <div class="space-y-3">
            <%= for {question, idx} <- Enum.with_index(@questions) do %>
              <.live_component
                module={QuestionLive}
                id={"question-#{question_id(question)}"}
                question={question}
                current_scope={@current_scope}
                poll={@poll}
                idx={idx}
                count={length(@questions)}
              />
            <% end %>
            <.add_question_button wide />
          </div>
        <% else %>
          <.no_questions_yet />
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp question_id(%{id: id}) when not is_nil(id), do: id
  defp question_id(%{temp_id: temp_id}), do: temp_id
  defp question_id(_), do: Ecto.UUID.generate()

  @impl true
  def handle_event("add_question", _params, socket) do
    max_position =
      socket.assigns.questions
      |> Enum.map(&Map.get(&1, :position, 0))
      |> Enum.max(fn -> 0 end)

    temp_question = %{
      temp_id: "temp_#{System.unique_integer([:positive])}",
      body: "",
      options: [],
      poll_id: socket.assigns.poll.id,
      editing: true,
      position: max_position + 1
    }

    questions = socket.assigns.questions ++ [temp_question]

    {:noreply, assign(socket, :questions, questions)}
  end

  # Messages from QuestionLive

  @impl true
  def handle_info({:select_question_body, _component_id, _body}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:add_temporary_option, question, new_option}, socket) do
    questions =
      Enum.map(socket.assigns.questions, fn q ->
        if matches_question?(q, question) do
          max_position =
            q.options
            |> Enum.map(& &1.position)
            |> Enum.max(fn -> 0 end)

          new_option = Map.put(new_option, :position, max_position + 1)

          Map.update(q, :options, [new_option], &(&1 ++ [new_option]))
        else
          q
        end
      end)

    {:noreply, assign(socket, :questions, questions)}
  end

  @impl true
  def handle_info({:question_created, new_question, temp_id}, socket) when is_binary(temp_id) do
    has_temp? =
      Enum.any?(
        socket.assigns.questions,
        fn q -> Map.get(q, :temp_id) == temp_id end
      )

    questions =
      if has_temp? do
        Enum.map(socket.assigns.questions, fn q ->
          if Map.get(q, :temp_id) == temp_id, do: new_question, else: q
        end)
      else
        socket.assigns.questions ++ [new_question]
      end

    {:noreply,
     socket
     |> assign(:questions, questions)
     |> put_flash(:info, "Question saved")}
  end

  @impl true
  def handle_info({:question_updated, updated_question}, socket) do
    questions =
      Enum.map(socket.assigns.questions, fn q ->
        if Map.get(q, :id) == updated_question.id, do: updated_question, else: q
      end)

    {:noreply,
     socket
     |> assign(:questions, questions)
     |> put_flash(:info, "Question updated")}
  end

  @impl true
  def handle_info({:question_deleted, question_id}, socket) do
    questions =
      Enum.reject(socket.assigns.questions, fn q ->
        Map.get(q, :id) == question_id or Map.get(q, :temp_id) == question_id
      end)

    flash? = not String.starts_with?(to_string(question_id), "temp_")

    socket =
      if flash? do
        put_flash(socket, :info, "Question deleted")
      else
        socket
      end

    {:noreply, assign(socket, :questions, questions)}
  end

  # Messages from OptionLive

  @impl true
  def handle_info({:select_option_body, _component_id, _body}, socket) do
    {:noreply, socket}
  end

  def handle_info({:option_created, new_option, temp_id: temp_id}, socket) do
    questions =
      Enum.map(socket.assigns.questions, fn question ->
        if Map.get(question, :id) == new_option.question_id or
             Map.get(question, :temp_id) == Map.get(new_option, :question_id) do
          new_options =
            question.options
            |> Enum.reject(fn opt -> Map.get(opt, :temp_id) == temp_id end)
            |> Kernel.++([new_option])

          %{question | options: new_options}
        else
          question
        end
      end)

    {:noreply,
     socket
     |> assign(:questions, questions)
     |> put_flash(:info, "Option created")}
  end

  def handle_info({:option_updated, updated_option}, socket) do
    questions =
      Enum.map(socket.assigns.questions, fn question ->
        if question.id == updated_option.question_id do
          new_options =
            Enum.map(question.options, fn opt ->
              if Map.get(opt, :id) == updated_option.id, do: updated_option, else: opt
            end)

          %{question | options: new_options}
        else
          question
        end
      end)

    {:noreply,
     socket
     |> assign(:questions, questions)
     |> put_flash(:info, "Option updated")}
  end

  def handle_info({:option_deleted, option_id}, socket) do
    questions =
      Enum.map(socket.assigns.questions, fn question ->
        new_options =
          Enum.reject(question.options, fn opt ->
            Map.get(opt, :id) == option_id or Map.get(opt, :temp_id) == option_id
          end)

        %{question | options: new_options}
      end)

    flash? = String.contains?(to_string(option_id), "temp_opt_") == false

    socket =
      if flash? do
        put_flash(socket, :info, "Option deleted")
      else
        socket
      end

    {:noreply, assign(socket, :questions, questions)}
  end

  def handle_info({:options_reordered, question}, socket) do
    questions =
      Enum.map(socket.assigns.questions, fn q ->
        if matches_question?(q, question) do
          %{q | options: Polling.list_options(socket.assigns.current_scope, q)}
        else
          q
        end
      end)

    {:noreply, assign(socket, :questions, questions)}
  end

  def handle_info({:questions_reordered, poll}, socket) do
    refreshed_poll =
      socket.assigns.current_scope
      |> Campaigns.get_poll!(poll.id)

    {:noreply,
     socket
     |> assign(:poll, refreshed_poll)
     |> assign(:questions, refreshed_poll.questions)}
  end

  @impl true
  # Global "app:visitors" presence_diff broadcasts. Questions editor does not
  # use the global visitor strip.
  def handle_info(%{topic: "app:visitors", event: "presence_diff"}, socket) do
    {:noreply, socket}
  end

  defp matches_question?(q, question) do
    Map.get(q, :id) == Map.get(question, :id) or
      (Map.get(q, :temp_id) && Map.get(q, :temp_id) == Map.get(question, :temp_id))
  end

  def no_questions_yet(assigns) do
    ~H"""
    <div class="rounded border border-dashed border-base-300 bg-base-200/50 px-4 py-5">
      <div class="flex flex-col items-center text-center gap-y-3">
        <div class="flex flex-row items-center justify-center gap-x-2">
          <.icon
            name="hero-question-mark-circle"
            class="size-8 text-base-content/50"
          />
          <p class="text-sm font-semibold text-base-content">No questions added yet!</p>
        </div>

        <.add_question_button />
      </div>
    </div>
    """
  end

  attr :wide, :boolean, default: false

  def add_question_button(assigns) do
    ~H"""
    <.button
      phx-click="add_question"
      class={["btn btn-primary", if(@wide, do: "btn-block")]}
    >
      <.icon name="hero-plus" /> Add Question
    </.button>
    """
  end

  # The global VisitorIdentity hook (in Layouts.app) fires this on every LV.
  # Tracking is handled centrally in GlobalPresence on_mount attach_hook.
  def handle_event("visitor-identified", _params, socket) do
    {:noreply, socket}
  end
end
