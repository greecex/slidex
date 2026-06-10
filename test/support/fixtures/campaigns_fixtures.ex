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
        title: "some title"
      })

    {:ok, poll} = Slidex.Campaigns.create_poll(scope, attrs)
    poll
  end
end
