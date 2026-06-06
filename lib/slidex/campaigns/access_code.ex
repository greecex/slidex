defmodule Slidex.Campaigns.AccessCode do
  # Crockford Base32 (no I, L, O, U)
  @alphabet "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
  @len 6
  @sep_every 3
  @sep "-"

  def generate do
    for _ <- 1..@len, into: "" do
      String.at(@alphabet, :rand.uniform(String.length(@alphabet)) - 1)
    end
    |> String.graphemes()
    |> Enum.chunk_every(@sep_every)
    |> Enum.intersperse(@sep)
    |> List.flatten()
    |> Enum.join()
  end
end
