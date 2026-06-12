defmodule Slidex.CampaignsFixtures do
  @moduledoc """
  Test helpers that build `Slidex.Campaigns` entities (polls).
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
