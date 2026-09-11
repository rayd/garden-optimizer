defmodule GardenOptimizer.Scheduling.Assignment do
  @moduledoc """
  Where and when one `garden_plant` unit goes into the ground, and which squares it holds.

  `plant_week` and `last_week` are *display* week numbers (week 1 = the earliest week anything in
  this garden could be planted). The unit occupies `cells` for every week in
  `plant_week..last_week` inclusive, and the squares free up at `last_week + 1`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias GardenOptimizer.Gardens.{GardenPlant, GrowingArea}
  alias GardenOptimizer.Scheduling.Schedule

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "plant_assignments" do
    field :plant_week, :integer
    field :plant_date, :date
    field :last_week, :integer
    field :removal_date, :date
    field :cells, {:array, :map}, default: []

    belongs_to :schedule, Schedule
    belongs_to :garden_plant, GardenPlant
    belongs_to :growing_area, GrowingArea

    timestamps(type: :utc_datetime)
  end

  def changeset(assignment, attrs) do
    assignment
    |> cast(attrs, [:plant_week, :plant_date, :last_week, :removal_date, :cells])
    |> validate_required([:plant_week, :plant_date, :last_week])
  end
end
