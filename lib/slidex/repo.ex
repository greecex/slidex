defmodule Slidex.Repo do
  use Ecto.Repo,
    otp_app: :slidex,
    adapter: Ecto.Adapters.Postgres

  @impl true
  def init(_, opts) do
    opts = Keyword.put(opts, :uuid, Ecto.ULID)
    {:ok, opts}
  end
end
