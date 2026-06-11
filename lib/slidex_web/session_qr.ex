defmodule SlidexWeb.SessionQR do
  @moduledoc """
  Builds the public join URL for a voting session and renders it as a QR code.

  The presenter view shows the QR so people in the room can scan it to reach
  the join page. Both the URL and the SVG derive from the session's unguessable
  slug, keeping this a thin, easily tested boundary over `QRCode` and the
  endpoint's verified routes.
  """
  use SlidexWeb, :verified_routes

  alias Slidex.Voting.Session

  @doc """
  The absolute join URL for a session, encoded in the QR code and shown to
  participants.

  ## Examples

      iex> SlidexWeb.SessionQR.join_url(%Slidex.Voting.Session{slug: "abc"}) |> String.ends_with?("/join/abc")
      true
  """
  def join_url(%Session{slug: slug}), do: url(~p"/join/#{slug}")

  @doc """
  Renders the session's join URL as an SVG QR code string, ready to embed in a
  template with `Phoenix.HTML.raw/1`. Returns an empty string on failure.

  ## Examples

      iex> SlidexWeb.SessionQR.svg(%Slidex.Voting.Session{slug: "abc"}) |> String.contains?("<svg")
      true
  """
  def svg(%Session{} = session, scale \\ 6) do
    # struct/2, not a %SvgSettings{} literal: Elixir 1.20's type checker
    # crashes building this dependency's struct literal.
    settings = struct(QRCode.Render.SvgSettings, scale: scale)

    case session |> join_url() |> QRCode.create() |> QRCode.render(:svg, settings) do
      {:ok, svg} -> svg
      {:error, _reason} -> ""
    end
  end
end
