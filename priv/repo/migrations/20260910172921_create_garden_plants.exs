defmodule GardenOptimizer.Repo.Migrations.CreateGardenPlants do
  use Ecto.Migration

  def change do
    # One row per plant *unit*: a quantity of 6 tomatoes is 6 rows. This is what lets a single
    # grid cell name the exact unit it holds.
    create table(:garden_plants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :garden_id, references(:gardens, type: :binary_id, on_delete: :delete_all), null: false
      add :plant_id, references(:plants, type: :binary_id, on_delete: :restrict), null: false

      # Optional user-set constraint pinning this unit to one bed. The scheduler reads it but
      # never writes it; the bed it actually resolved to lives on the assignment.
      add :growing_area_id,
          references(:growing_areas, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:garden_plants, [:garden_id])
    create index(:garden_plants, [:plant_id])
    create index(:garden_plants, [:growing_area_id])
  end
end
