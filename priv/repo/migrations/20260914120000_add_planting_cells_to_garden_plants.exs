defmodule GardenOptimizer.Repo.Migrations.AddPlantingCellsToGardenPlants do
  use Ecto.Migration

  @moduledoc """
  Lets a plant unit be pinned to the exact squares it occupies, not just its bed.

  Pinning only a bed and a window let the placer move a filled unit anywhere in the bed on every
  re-solve, so the squares a gardener filled did not fill up in any order they could predict.

  Nullable: `nil` means the unit is free to take any squares its other pins allow. Rows filled
  before this column existed keep behaving as bed-and-window pins.
  """

  def change do
    alter table(:garden_plants) do
      # Same shape as plant_assignments.cells: [%{"row" => r, "col" => c}].
      add :planting_cells, {:array, :map}
    end
  end
end
