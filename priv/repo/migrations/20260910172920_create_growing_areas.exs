defmodule GardenOptimizer.Repo.Migrations.CreateGrowingAreas do
  use Ecto.Migration

  def change do
    create table(:growing_areas, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :width_in, :integer, null: false
      add :length_in, :integer, null: false
      add :garden_id, references(:gardens, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:growing_areas, [:garden_id])
  end
end
