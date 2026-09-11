defmodule GardenOptimizer.Scheduling.Unit do
  @moduledoc """
  One plant unit awaiting placement: which `garden_plant` row it is, what it is, and whether the
  user pinned it to a particular bed.
  """
  @enforce_keys [:id, :plant]
  defstruct [:id, :plant, :pinned_area_id]

  @type t :: %__MODULE__{
          id: term(),
          plant: GardenOptimizer.Plants.Plant.t(),
          pinned_area_id: term() | nil
        }
end
