defmodule GardenOptimizer.Scheduling.Strategy do
  @moduledoc """
  How planting weeks and squares get chosen.

  The scheduler depends on this behaviour rather than on any particular policy, so a packing
  optimizer can replace the shipped earliest-fit strategy without touching the schema, the
  persistence layer, or the UI.
  """

  alias GardenOptimizer.Scheduling.{Area, Occupancy, Placement, Unit, WeekGrid}

  @doc """
  Place as many `units` as possible.

  Returns the placements made, the resulting occupancy grid (which free-block detection reads),
  and a map of `unit_id => reason` for anything that would not fit.
  """
  @callback assign(WeekGrid.t(), [Area.t()], [Unit.t()]) ::
              {[Placement.t()], Occupancy.t(), %{optional(term()) => atom()}}
end
