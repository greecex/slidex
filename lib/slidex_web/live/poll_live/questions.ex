defmodule SlidexWeb.PollLive.Questions do
  use SlidexWeb, :live_view

  alias Slidex.Campaigns

  alias Slidex.Repo
  alias SlidexWeb.PollLive.Components.QuestionLive

  @impl true
  def mount(%{"id" => poll_id}, _session, socket) do
    poll =
      socket.assigns.current_scope
      |> Campaigns.get_poll!(poll_id)
      |> Repo.preload(questions: [:options])

    {:ok,
     socket
     |> assign(:poll, poll)
     |> assign(:questions, poll.questions)
     |> assign(:page_title, "Manage Questions")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Manage Questions
        <:subtitle>{@poll.title}</:subtitle>
        <:actions>
          <.button navigate={~p"/polls/#{@poll}"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.add_question_button :if={@questions != []} />
        </:actions>
      </.header>

      <div class="mt-8 space-y-8">
        <div
          :if={@questions == []}
          class="card w-full bg-base-100 shadow border border-dashed border-base-300"
        >
          <div class="card-body items-center">
            <.icon name="hero-face-frown" class="size-12 text-neutral" />
            <h2 class="card-title text-md">
              No questions yet
            </h2>
            <.add_question_button />
          </div>
        </div>

        <div :if={@questions != []} class="flex flex-col gap-y-2">
          <%= for question <- @questions do %>
            <.live_component
              module={QuestionLive}
              id={"question-#{question_id(question)}"}
              question={question}
              current_scope={@current_scope}
              poll={@poll}
            />
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp question_id(%{id: id}) when not is_nil(id), do: id
  defp question_id(%{temp_id: temp_id}), do: temp_id
  defp question_id(_), do: Ecto.UUID.generate()

  @impl true
  def handle_event("add_question", _params, socket) do
    temp_question = %{
      temp_id: "temp_#{System.unique_integer([:positive])}",
      body: "",
      options: [],
      poll_id: socket.assigns.poll.id
    }

    questions = socket.assigns.questions ++ [temp_question]

    {:noreply, assign(socket, :questions, questions)}
  end

  @impl true
  def handle_info({:select_question_body, _component_id, _body}, socket) do
    {:noreply, socket}
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

    {:noreply, assign(socket, :questions, questions)}
  end

  @impl true
  def handle_info({:question_deleted, question_id}, socket) do
    questions =
      Enum.reject(socket.assigns.questions, fn q ->
        Map.get(q, :id) == question_id or Map.get(q, :temp_id) == question_id
      end)

    {:noreply, assign(socket, :questions, questions)}
  end

  def add_question_button(assigns) do
    ~H"""
    <.button phx-click="add_question" variant="primary">
      <.icon name="hero-plus" /> Add Question
    </.button>
    """
  end
end
