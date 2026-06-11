defmodule SlidexWeb.Presence do
  @moduledoc """
  Phoenix Presence tracker for live voting sessions.

  Used by VoteLive to show a real-time "X participating" count and a strip
  of identicons (using IdenticonSvg) for everyone currently connected to
  a given /vote/:slug session.

  Each participant is tracked under a stable key:
  - "user:<user_id>" for authenticated participants (including the MC)
  - "visitor:<visitor_id>" for guests (the id lives in their browser localStorage)

  The metas can carry extra info such as the display seed for the identicon
  and a human label when available.
  """

  use Phoenix.Presence,
    otp_app: :slidex,
    pubsub_server: Slidex.PubSub

  @doc """
  Returns the presence topic for a given session slug.
  """
  def topic(slug) when is_binary(slug), do: "presence:session:#{slug}"

  @doc """
  Tracks a participant in the session's presence.

  Call this from the LiveView after identity (user or visitor) has been resolved.
  """
  def track_participant(pid, slug, key, meta) when is_binary(slug) and is_binary(key) do
    track(pid, topic(slug), key, meta)
  end

  @doc """
  Stops tracking a participant (usually called from terminate/2 in the LiveView).
  """
  def untrack_participant(pid, slug, key) when is_binary(slug) and is_binary(key) do
    untrack(pid, topic(slug), key)
  end

  @doc """
  Lists all currently present participants for the slug.

  Returns a map of key => %{metas: [meta, ...]} which the LiveView can turn
  into a nice list for identicons.
  """
  def list_participants(slug) when is_binary(slug) do
    list(topic(slug))
  end

  @doc """
  Track a global visitor (user or guest) on the app-wide visitors topic.
  """
  def track_global(pid, key, meta) do
    track(pid, "app:visitors", key, meta)
  end

  @doc "List all current global visitors."
  def list_global do
    list("app:visitors")
  end
end
