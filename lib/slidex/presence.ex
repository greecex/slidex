defmodule Slidex.Presence do
  @moduledoc """
  Tracks who is present in a live voting session.

  Presence is keyed by the session room topic (`Slidex.Voting.session_topic/1`),
  the same topic used for live lifecycle, question, and results events. The
  presenter and participant views both track on connect, so a single roster
  holds the host, logged in voters, and guests, each tagged with a `role`.

  Each tracked entry carries a `display_name`, a `role` (`:owner`, `:user`, or
  `:guest`), and `joined_at` (a millisecond timestamp used only for ordering).
  """
  use Phoenix.Presence, otp_app: :slidex, pubsub_server: Slidex.PubSub

  @doc """
  Lists the people currently present on `topic` as a roster.

  Reads live presence state and reduces it with `roster/1`.
  """
  def list_present(topic) when is_binary(topic) do
    topic
    |> list()
    |> roster()
  end

  @doc """
  Reduces a `Phoenix.Presence` map into a roster: one entry per present person,
  each `%{display_name: ..., role: ...}`, ordered by join time.

  Several connections from the same person share a presence key (and so several
  metas); they collapse to a single roster entry.

  ## Examples

      iex> presences = %{
      ...>   "owner" => %{metas: [%{display_name: "Ada", role: :owner, joined_at: 1}]},
      ...>   "guest-1" => %{metas: [%{display_name: nil, role: :guest, joined_at: 2}]}
      ...> }
      iex> Slidex.Presence.roster(presences)
      [%{display_name: "Ada", role: :owner}, %{display_name: nil, role: :guest}]
  """
  def roster(presences) when is_map(presences) do
    presences
    |> Map.values()
    |> Enum.map(fn %{metas: [meta | _]} -> meta end)
    |> Enum.sort_by(& &1.joined_at)
    |> Enum.map(&%{display_name: &1.display_name, role: &1.role})
  end

  @doc """
  Splits a roster (from `roster/1`) into named people and a count of anonymous
  guests, for a compact presence display.

  Owners and logged in users are returned individually under `:named`, in join
  order; everyone with the `:guest` role collapses into the `:guests` count, so
  a room with many guests stays readable.

  ## Examples

      iex> Slidex.Presence.summary([
      ...>   %{display_name: "Ada", role: :owner},
      ...>   %{display_name: "Boris", role: :user},
      ...>   %{display_name: nil, role: :guest},
      ...>   %{display_name: nil, role: :guest}
      ...> ])
      %{guests: 2, named: [%{display_name: "Ada", role: :owner}, %{display_name: "Boris", role: :user}]}
  """
  def summary(roster) when is_list(roster) do
    {guests, named} = Enum.split_with(roster, &(&1.role == :guest))
    %{named: named, guests: length(guests)}
  end
end
