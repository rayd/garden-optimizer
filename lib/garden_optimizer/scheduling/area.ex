defmodule GardenOptimizer.Scheduling.Area do
  @moduledoc """
  A growing area reduced to what the algorithm needs: an id and a grid of whole 6" squares.
  """
  @enforce_keys [:id, :rows, :cols]
  defstruct [:id, :rows, :cols, :name]

  alias GardenOptimizer.Gardens.GrowingArea

  @type t :: %__MODULE__{
          id: term(),
          rows: non_neg_integer(),
          cols: non_neg_integer(),
          name: String.t() | nil
        }

  @doc "Project a persisted growing area onto its plain grid representation."
  def from_schema(%GrowingArea{} = area) do
    %__MODULE__{
      id: area.id,
      rows: GrowingArea.rows(area),
      cols: GrowingArea.cols(area),
      name: area.name
    }
  end

  @doc "Every `{row, col}` in the area, row-major."
  def cells(%__MODULE__{rows: rows, cols: cols}) do
    for r <- 0..(rows - 1)//1, c <- 0..(cols - 1)//1, do: {r, c}
  end
end
