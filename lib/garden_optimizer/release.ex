defmodule GardenOptimizer.Release do
  @moduledoc """
  Used to run migrations and seed data in production.
  Called by the docker-entrypoint.sh script.
  """

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def seed do
    load_app()

    # Run the seed script
    seed_script = Application.app_dir(:garden_optimizer, "priv/repo/seeds.exs")

    if File.exists?(seed_script) do
      {:ok, _} = Code.eval_file(seed_script)
    end
  end

  defp repos do
    Application.load(:garden_optimizer)
    Application.fetch_env!(:garden_optimizer, :ecto_repos)
  end

  defp load_app do
    Application.load(:garden_optimizer)
  end
end
