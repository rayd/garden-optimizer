defmodule GardenOptimizer.Scheduling.Unit do
  @moduledoc """
  One plant unit awaiting placement: which `garden_plant` row it is, what it is, and whatever the
  gardener has pinned about where and when it goes.

  `pinned_area_id` holds it to one bed; `pinned_range` holds it to a span of frost-relative week
  indices; `pinned_cells` holds it to squares within that bed — every square it takes must be one
  of them. Dates are converted to indices on the way in, so the pure core never deals in calendars.
  """
  @enforce_keys [:id, :plant]
  defstruct [:id, :plant, :pinned_area_id, :pinned_range, :pinned_cells]

  @type cell :: {non_neg_integer(), non_neg_integer()}

  @type t :: %__MODULE__{
          id: term(),
          plant: GardenOptimizer.Plants.Plant.t(),
          pinned_area_id: term() | nil,
          pinned_range: {integer(), integer()} | nil,
          pinned_cells: MapSet.t(cell()) | nil
        }

  @doc """
  True when the gardener has fixed both the bed and the window for this unit.
  """
  @spec fully_pinned?(t()) :: boolean()
  def fully_pinned?(%__MODULE__{pinned_area_id: area, pinned_range: range}),
    do: not is_nil(area) and not is_nil(range)

  @doc """
  How constrained a unit is, lowest first: pinned to squares (fewest squares first), then pinned to
  a bed and a window, then free.

  Among units that can go in the same week, the more constrained are placed first, so they claim
  their squares before anything with more freedom competes for them.
  """
  @spec constraint_rank(t()) :: {0 | 1 | 2, non_neg_integer()}
  def constraint_rank(%__MODULE__{pinned_cells: %MapSet{} = cells}), do: {0, MapSet.size(cells)}

  def constraint_rank(%__MODULE__{} = unit),
    do: if(fully_pinned?(unit), do: {1, 0}, else: {2, 0})
end
