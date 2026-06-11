defmodule SlidexWeb.SessionQRTest do
  use ExUnit.Case, async: true

  alias Slidex.Voting.Session
  alias SlidexWeb.SessionQR

  doctest SlidexWeb.SessionQR

  test "join_url/1 builds an absolute URL to the join page" do
    url = SessionQR.join_url(%Session{slug: "abc123"})

    assert String.starts_with?(url, "http")
    assert String.ends_with?(url, "/join/abc123")
  end
end
