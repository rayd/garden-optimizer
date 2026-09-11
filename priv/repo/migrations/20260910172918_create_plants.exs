defmodule GardenOptimizer.Repo.Migrations.CreatePlants do
  use Ecto.Migration

  def change do
    create table(:plants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :variety_name, :string, null: false
      add :common_type, :string, null: false
      add :sq_in, :integer, null: false
      add :planting_anchor, :string, null: false
      add :anchor_offset_weeks_min, :integer, null: false
      add :anchor_offset_weeks_max, :integer, null: false
      add :days_to_maturity, :integer, null: false
      add :harvest_type, :string, null: false
      add :source_url, :string

      timestamps(type: :utc_datetime)
    end

    # Re-importing the same URL updates the existing plant rather than duplicating it.
    create unique_index(:plants, [:source_url])
  end
end
