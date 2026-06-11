defmodule Slidex.PresenceTest do
  use ExUnit.Case, async: true

  doctest Slidex.Presence

  describe "roster/1" do
    test "dedupes by key, orders by join time, and keeps role and name" do
      presences = %{
        "p2" => %{metas: [%{display_name: nil, role: :guest, joined_at: 30}]},
        "owner" => %{metas: [%{display_name: "Ada", role: :owner, joined_at: 10}]},
        "p1" => %{
          metas: [
            %{display_name: "Boris", role: :user, joined_at: 20},
            %{display_name: "Boris", role: :user, joined_at: 25}
          ]
        }
      }

      assert Slidex.Presence.roster(presences) == [
               %{display_name: "Ada", role: :owner},
               %{display_name: "Boris", role: :user},
               %{display_name: nil, role: :guest}
             ]
    end

    test "is empty when no one is present" do
      assert Slidex.Presence.roster(%{}) == []
    end
  end

  describe "summary/1" do
    test "lists named people and collapses guests into a count" do
      roster = [
        %{display_name: "Ada", role: :owner},
        %{display_name: "Boris", role: :user},
        %{display_name: nil, role: :guest},
        %{display_name: nil, role: :guest},
        %{display_name: nil, role: :guest}
      ]

      assert Slidex.Presence.summary(roster) == %{
               named: [
                 %{display_name: "Ada", role: :owner},
                 %{display_name: "Boris", role: :user}
               ],
               guests: 3
             }
    end

    test "is empty for an empty roster" do
      assert Slidex.Presence.summary([]) == %{named: [], guests: 0}
    end
  end
end
