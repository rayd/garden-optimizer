defmodule GardenOptimizer.Gardens.GardenPlant do
  @moduledoc """
  One *unit* of a plant in a garden — a single tomato, not "six tomatoes".

  Quantity is expressed as row count, which is what allows the schedule grid to name the exact
  unit occupying a square.

  A unit may be pinned: `growing_area_id` fixes the bed, and `planting_window_start/end` fix the
  span of dates it may go in. The scheduler honours both but never writes them — a pin is an input
  to placement, not a result of it. Pinning a *window* rather than an exact date leaves the placer
  free to choose the week inside it, and pinning neither the squares nor the week means a future
  optimizer keeps real room to work within the bed.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias GardenOptimizer.Gardens.{Garden, GrowingArea}
  alias GardenOptimizer.Plants.Plant

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @origins [:manual, :block_fill]

  schema "garden_plants" do
    field :planting_window_start, :date
    field :planting_window_end, :date

    # Who chose this unit's constraints. Deliberately separate from "is there a window": the two
    # answer different questions, and they come apart as soon as anything but a person sets a pin.
    field :origin, Ecto.Enum, values: @origins, default: :manual

    belongs_to :garden, Garden
    belongs_to :plant, Plant
    belongs_to :growing_area, GrowingArea

    timestamps(type: :utc_datetime)
  end

  @doc "Values `origin` may take."
  def origins, do: @origins

  @doc "True when this unit is held to a span of dates."
  def pinned?(%__MODULE__{planting_window_start: nil}), do: false
  def pinned?(%__MODULE__{}), do: true

  def changeset(garden_plant, attrs) do
    garden_plant
    |> cast(attrs, [:growing_area_id, :planting_window_start, :planting_window_end, :origin])
    |> validate_window()
    |> foreign_key_constraint(:growing_area_id)
    |> check_constraint(:planting_window_end,
      name: :planting_window_ordered,
      message: "must not end before the window starts"
    )
  end

  # A half-open window is meaningless to the placer, so require both ends or neither.
  defp validate_window(changeset) do
    start = get_field(changeset, :planting_window_start)
    finish = get_field(changeset, :planting_window_end)

    cond do
      is_nil(start) and is_nil(finish) ->
        changeset

      is_nil(start) or is_nil(finish) ->
        add_error(changeset, :planting_window_start, "needs both a start and an end")

      Date.compare(finish, start) == :lt ->
        add_error(changeset, :planting_window_end, "must not end before the window starts")

      true ->
        changeset
    end
  end
end
