defmodule SlidexWeb.GlobalPresence do
  @moduledoc """
  On-mount hook to track all visitors (logged-in users and guests) in a global
  Phoenix.Presence topic ("app:visitors").

  - For authenticated users: tracks immediately on mount (if connected).
  - For guests: tracks when the VisitorIdentity hook pushes "visitor-identified".
  - Attaches a handle_event hook so the tracking works across all LiveViews
    without duplicating code in each module.
  - Also subscribes the LV to presence diffs for live updates.
  """

  import Phoenix.LiveView

  alias SlidexWeb.Presence
  alias SlidexWeb.Endpoint

  def on_mount(:track, _params, _session, socket) do
    if connected?(socket) do
      # Track logged-in user immediately
      socket =
        case socket.assigns[:current_scope] do
          %{user: %{id: id, username: username, email: email} = user} when not is_nil(user) ->
            key = "user:#{id}"
            meta = %{seed: username || email, label: username || "User"}
            Presence.track_global(self(), key, meta)
            Endpoint.subscribe("app:visitors")
            socket

          _ ->
            socket
        end

      # Attach hook to handle "visitor-identified" from the global hook div
      # (for guests, and also for logged-in as fallback/unification)
      socket =
        attach_hook(socket, :global_visitor, :handle_event, fn
          "visitor-identified", %{"visitor_id" => vid}, socket ->
            if connected?(socket) do
              key =
                case socket.assigns[:current_scope] do
                  %{user: %{id: id}} -> "user:#{id}"
                  _ -> "visitor:#{vid}"
                end

              meta =
                case socket.assigns[:current_scope] do
                  %{user: %{username: u, email: e} = user} when not is_nil(user) ->
                    %{seed: u || e, label: u || "User"}

                  _ ->
                    %{seed: vid, label: "Guest"}
                end

              Presence.track_global(self(), key, meta)
              Endpoint.subscribe("app:visitors")
            end

            {:cont, socket}

          _event, _params, socket ->
            {:cont, socket}
        end)

      {:cont, socket}
    else
      {:cont, socket}
    end
  end
end
