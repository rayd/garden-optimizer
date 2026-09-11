defmodule GardenOptimizer.Repo.Migrations.AddPlantingWindowToGardenPlants do
  use Ecto.Migration

  @moduledoc """
  Lets a plant unit be pinned to a bed and a span of dates.

  Filling a free planting block means saying "this goes in this bed, in this window". Storing that
  on the unit rather than materializing assignments keeps one placement code path and means the
  choice survives a re-build, which re-solves from `garden_plants`.

  The window is stored as dates rather than week numbers because display week 1 is defined by the
  earliest plantable week in the garden, so it shifts whenever the plant list changes -- a stored
  week number would quietly come to mean a different date.
  """

  def change do
    alter table(:garden_plants) do
      add :planting_window_start, :date
      add :planting_window_end, :date

      # Whether a person chose this unit's constraints or the tool did. Distinct from "is it
      # pinned": a future optimizer freezing part of a layout would set a window too, and it needs
      # to know which constraints are the gardener's intent and which are its own to relax.
      add :origin, :string, null: false, default: "manual"
    end

    create constraint(:garden_plants, :planting_window_ordered,
             check: """
             (planting_window_start IS NULL AND planting_window_end IS NULL)
             OR (planting_window_start IS NOT NULL AND planting_window_end IS NOT NULL
                 AND planting_window_start <= planting_window_end)
             """
           )

    create index(:garden_plants, [:garden_id, :origin])
  end
end
