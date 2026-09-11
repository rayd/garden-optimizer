defmodule GardenOptimizer.Repo.Migrations.CreateSchedules do
  use Ecto.Migration

  def change do
    create table(:garden_schedules, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :garden_id, references(:gardens, type: :binary_id, on_delete: :delete_all), null: false
      add :generated_at, :utc_datetime, null: false
      add :week_1_start_date, :date, null: false
      add :week_count, :integer, null: false
      # garden_plants that could not be placed anywhere in their eligible window.
      add :unplaced, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    # One live schedule per garden; re-building replaces it.
    create unique_index(:garden_schedules, [:garden_id])

    create table(:plant_assignments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :schedule_id,
          references(:garden_schedules, type: :binary_id, on_delete: :delete_all),
          null: false

      add :garden_plant_id,
          references(:garden_plants, type: :binary_id, on_delete: :delete_all),
          null: false

      add :growing_area_id,
          references(:growing_areas, type: :binary_id, on_delete: :delete_all),
          null: false

      add :plant_week, :integer, null: false
      add :plant_date, :date, null: false
      add :last_week, :integer, null: false
      add :removal_date, :date
      # [%{"row" => r, "col" => c}] - the squares this unit occupies.
      add :cells, {:array, :map}, null: false, default: []

      timestamps(type: :utc_datetime)
    end

    create index(:plant_assignments, [:schedule_id])
    create index(:plant_assignments, [:garden_plant_id])

    create table(:free_planting_blocks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :schedule_id,
          references(:garden_schedules, type: :binary_id, on_delete: :delete_all),
          null: false

      add :growing_area_id,
          references(:growing_areas, type: :binary_id, on_delete: :delete_all),
          null: false

      add :row, :integer, null: false
      add :col, :integer, null: false
      add :start_week, :integer, null: false
      add :start_date, :date, null: false
      add :weeks_available, :integer, null: false
    end

    create index(:free_planting_blocks, [:schedule_id])
    create index(:free_planting_blocks, [:schedule_id, :start_week])
  end
end
