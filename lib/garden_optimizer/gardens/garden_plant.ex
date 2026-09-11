defmodule GardenOptimizer.Gardens.GardenPlant do
  @moduledoc """
  One *unit* of a plant in a garden — a single tomato, not "six tomatoes".

  Quantity is expressed as row count, which is what allows the schedule grid to name the exact
  unit occupying a square. `growing_area_id` is an optional user constraint pinning this unit to
  one bed; the scheduler honours it but never writes it.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias GardenOptimizer.Gardens.{Garden, GrowingArea}
  alias GardenOptimizer.Plants.Plant

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "garden_plants" do
    belongs_to :garden, Garden
    belongs_to :plant, Plant
    belongs_to :growing_area, GrowingArea

    timestamps(type: :utc_datetime)
  end

  def changeset(garden_plant, attrs) do
    garden_plant
    |> cast(attrs, [:growing_area_id])
    |> foreign_key_constraint(:growing_area_id)
  end
end
