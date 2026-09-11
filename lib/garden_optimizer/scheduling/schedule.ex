defmodule GardenOptimizer.Scheduling.Schedule do
  @moduledoc """
  A generated planting schedule for a garden. One per garden — re-building replaces it.

  The `weeks -> growing_areas -> squares` grid is *derived* from `plant_assignments` on demand
  (see `GardenOptimizer.Scheduling.Output`) rather than stored, which keeps a season's worth of
  ~30k grid cells out of the database.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias GardenOptimizer.Gardens.Garden
  alias GardenOptimizer.Scheduling.{Assignment, FreeBlock}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "garden_schedules" do
    field :generated_at, :utc_datetime
    field :week_1_start_date, :date
    field :week_count, :integer
    field :unplaced, :map, default: %{}

    belongs_to :garden, Garden

    has_many :assignments, Assignment,
      foreign_key: :schedule_id,
      preload_order: [asc: :plant_week]

    has_many :free_blocks, FreeBlock,
      foreign_key: :schedule_id,
      preload_order: [asc: :start_week, desc: :weeks_available]

    timestamps(type: :utc_datetime)
  end

  def changeset(schedule, attrs) do
    schedule
    |> cast(attrs, [:generated_at, :week_1_start_date, :week_count, :unplaced])
    |> validate_required([:generated_at, :week_1_start_date, :week_count])
  end
end
