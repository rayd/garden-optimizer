defmodule GardenOptimizer.Scheduling.FreeBlock do
  @moduledoc """
  A single 6" x 6" square that sits *completely* empty for 5 or more consecutive weeks — the
  succession-planting opportunities the tool exists to surface.

  A square holding even one small plant is not free, so partly-filled shared squares never appear
  here.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias GardenOptimizer.Gardens.GrowingArea
  alias GardenOptimizer.Scheduling.Schedule

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @minimum_weeks 5

  schema "free_planting_blocks" do
    field :row, :integer
    field :col, :integer
    field :start_week, :integer
    field :start_date, :date
    field :weeks_available, :integer

    belongs_to :schedule, Schedule
    belongs_to :growing_area, GrowingArea
  end

  @doc "Shortest run of empty weeks that counts as a free planting block."
  def minimum_weeks, do: @minimum_weeks

  def changeset(block, attrs) do
    block
    |> cast(attrs, [:row, :col, :start_week, :start_date, :weeks_available])
    |> validate_required([:row, :col, :start_week, :start_date, :weeks_available])
  end
end
