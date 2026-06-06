defmodule Slidex.Repo do
  use Ecto.Repo,
    otp_app: :slidex,
    adapter: Ecto.Adapters.Postgres
end
