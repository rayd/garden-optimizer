defmodule GardenOptimizer.Scheduling.Placement do
  @moduledoc """
  The algorithm's decision for one unit: which bed, which week, and which squares.

  Weeks are frost-relative indices here; they are converted to display week numbers on the way
  into the database.
  """
  @enforce_keys [:unit_id, :area_id, :plant_index, :last_index, :cells]
  defstruct [:unit_id, :area_id, :plant_index, :last_index, :cells]

  @type t :: %__MODULE__{
          unit_id: term(),
          area_id: term(),
          plant_index: integer(),
          last_index: integer(),
          cells: [{non_neg_integer(), non_neg_integer()}]
        }
end
