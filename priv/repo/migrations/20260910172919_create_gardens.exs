defmodule GardenOptimizer.Repo.Migrations.CreateGardens do
  use Ecto.Migration

  def change do
    create table(:gardens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :zip_code, :string, null: false
      add :last_frost_date, :date, null: false
      add :first_frost_date, :date, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
