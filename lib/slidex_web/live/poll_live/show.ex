defmodule SlidexWeb.PollLive.Show do
  use SlidexWeb, :live_view

  alias Slidex.Campaigns

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Poll {@poll.id}
        <:subtitle>This is a poll record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/polls"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/polls/#{@poll}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit poll
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Title">{@poll.title}</:item>
        <:item title="Is public">{@poll.is_public}</:item>
        <:item title="Access code">{@poll.access_code}</:item>
        <:item title="Expires at">{@poll.expires_at}</:item>
        <:item title="Closed at">{@poll.closed_at}</:item>
        <:item title="Archived at">{@poll.archived_at}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Campaigns.subscribe_polls(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Show Poll")
     |> assign(:poll, Campaigns.get_poll!(socket.assigns.current_scope, id, [:questions]))}
  end

  @impl true
  def handle_info(
        {:updated, %Slidex.Campaigns.Poll{id: id} = poll},
        %{assigns: %{poll: %{id: id}}} = socket
      ) do
    {:noreply, assign(socket, :poll, poll)}
  end

  def handle_info(
        {:deleted, %Slidex.Campaigns.Poll{id: id}},
        %{assigns: %{poll: %{id: id}}} = socket
      ) do
    {:noreply,
     socket
     |> put_flash(:error, "The current poll was deleted.")
     |> push_navigate(to: ~p"/polls")}
  end

  def handle_info({type, %Slidex.Campaigns.Poll{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply, socket}
  end
end
