defmodule GardenOptimizer.Scheduling.FreeBlocks do
  @moduledoc """
  Finds the succession-planting opportunities in a finished layout.

  A *free planting block* is one 6" x 6" square that stays completely empty for five or more
  consecutive weeks. "Completely" is the operative word: a square holding a single radish is
  working, not free, so partly-filled shared squares never qualify.
  """

  alias GardenOptimizer.Scheduling.{Area, FreeBlock, Occupancy, WeekGrid}

  @minimum_weeks FreeBlock.minimum_weeks()

  @type block :: %{
          area_id: term(),
          row: non_neg_integer(),
          col: non_neg_integer(),
          start_index: integer(),
          weeks_available: pos_integer()
        }

  @doc """
  Every free block in the layout, ordered by start week then by longest span.
  """
  @spec detect(WeekGrid.t(), [Area.t()], Occupancy.t()) :: [block()]
  def detect(%WeekGrid{} = grid, areas, occupancy) do
    indices = WeekGrid.indices(grid)

    areas
    |> Enum.flat_map(fn area ->
      Enum.flat_map(Area.cells(area), fn {row, col} ->
        indices
        |> runs_of_empty_weeks({area.id, row, col}, occupancy)
        |> Enum.map(fn {start_index, weeks} ->
          %{
            area_id: area.id,
            row: row,
            col: col,
            start_index: start_index,
            weeks_available: weeks
          }
        end)
      end)
    end)
    |> Enum.sort_by(&{&1.start_index, -&1.weeks_available})
  end

  # Walk the season for one square, emitting each maximal run of empty weeks long enough to count.
  defp runs_of_empty_weeks(indices, key, occupancy) do
    {runs, open} =
      Enum.reduce(indices, {[], nil}, fn index, {runs, open} ->
        case {Occupancy.empty?(occupancy, key, index), open} do
          {true, nil} -> {runs, {index, 1}}
          {true, {start, len}} -> {runs, {start, len + 1}}
          {false, nil} -> {runs, nil}
          {false, run} -> {[run | runs], nil}
        end
      end)

    [open | runs]
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(fn {_start, len} -> len >= @minimum_weeks end)
    |> Enum.reverse()
  end
end
