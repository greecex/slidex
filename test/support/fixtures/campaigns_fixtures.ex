defmodule Slidex.CampaignsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Slidex.Campaigns` context.
  """

  @doc """
  Generate a poll.
  """
  def poll_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        access_code: "some access_code",
        archived_at: ~U[2026-06-05 14:14:00.000000Z],
        closed_at: ~U[2026-06-05 14:14:00Z],
        expires_at: ~U[2026-06-05 14:14:00Z],
        is_public: true,
        title: "some title"
      })

    {:ok, poll} = Slidex.Campaigns.create_poll(scope, attrs)
    poll
  end
end
