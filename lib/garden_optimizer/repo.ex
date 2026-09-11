defmodule GardenOptimizer.Repo do
  use Ecto.Repo,
    otp_app: :garden_optimizer,
    adapter: Ecto.Adapters.Postgres
end
