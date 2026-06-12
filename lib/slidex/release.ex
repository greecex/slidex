defmodule Slidex.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :slidex

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  # Seeds the database by evaluating priv/repo/seeds.exs. Idempotent.
  # Run once after the first deploy: bin/slidex eval "Slidex.Release.seed()"
  def seed do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(Slidex.Repo, fn _repo ->
        Code.eval_file(Application.app_dir(@app, "priv/repo/seeds.exs"))
      end)
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
