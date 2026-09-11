defmodule GardenOptimizer.Scheduling.Unit do
  @moduledoc """
  One plant unit awaiting placement: which `garden_plant` row it is, what it is, and whatever the
  gardener has pinned about where and when it goes.

  `pinned_area_id` holds it to one bed; `pinned_range` holds it to a span of frost-relative week
  indices. Dates are converted to indices on the way in, so the pure core never deals in calendars.
  """
  @enforce_keys [:id, :plant]
  defstruct [:id, :plant, :pinned_area_id, :pinned_range]

  @type t :: %__MODULE__{
          id: term(),
          plant: GardenOptimizer.Plants.Plant.t(),
          pinned_area_id: term() | nil,
          pinned_range: {integer(), integer()} | nil
        }

  @doc """
  True when the gardener has fixed both the bed and the window for this unit.

  Fully pinned units are placed before anything else, so they claim their squares before the
  free-floating units compete for them.
  """
  @spec fully_pinned?(t()) :: boolean()
  def fully_pinned?(%__MODULE__{pinned_area_id: area, pinned_range: range}),
    do: not is_nil(area) and not is_nil(range)
end
