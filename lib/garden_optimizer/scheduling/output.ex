defmodule GardenOptimizer.Scheduling.Output do
  @moduledoc """
  Materializes the specified `weeks -> growing_areas -> squares` structure.

  The grid is derived from assignments on demand rather than stored: a season for the sample
  garden is roughly 800 squares x 35 weeks, and rebuilding it from a few hundred assignment rows
  is far cheaper than keeping ~28,000 cells in the database.

  Each cell is a **list** of `garden_plants.id`: one entry for a square held by a large plant,
  several for a square shared by small ones, and `[]` for a free square.
  """

  alias GardenOptimizer.Scheduling.{Area, Assignment, Schedule, WeekGrid}

  @doc """
  Build the full structure for a persisted schedule.

  Pass `weeks: [n, ...]` to materialize only certain display weeks — the UI renders one week at a
  time and has no reason to build the rest.
  """
  def build(%Schedule{} = schedule, areas, opts \\ []) do
    areas = Enum.map(areas, &Area.from_schema/1)
    assignments = schedule.assignments

    week_numbers =
      case Keyword.get(opts, :weeks) do
        nil -> Enum.to_list(1..schedule.week_count//1)
        weeks -> weeks
      end

    %{
      weeks:
        Enum.map(week_numbers, fn week ->
          %{
            week: week,
            start_date: Date.add(schedule.week_1_start_date, (week - 1) * 7),
            growing_areas: Enum.map(areas, &area_grid(&1, assignments, week))
          }
        end)
    }
  end

  @doc "Squares for one bed in one display week, as an n x m list of lists of ids."
  def area_grid(%Area{} = area, assignments, week) do
    occupants =
      assignments
      |> Enum.filter(fn a ->
        a.growing_area_id == area.id and a.plant_week <= week and week <= a.last_week
      end)
      |> Enum.reduce(%{}, fn %Assignment{} = a, acc ->
        Enum.reduce(a.cells, acc, fn cell, inner ->
          Map.update(inner, cell_key(cell), [a.garden_plant_id], &[a.garden_plant_id | &1])
        end)
      end)

    squares =
      for r <- 0..(area.rows - 1)//1 do
        for c <- 0..(area.cols - 1)//1 do
          occupants |> Map.get({r, c}, []) |> Enum.reverse()
        end
      end

    %{id: area.id, name: area.name, squares: squares}
  end

  # Cells round-trip through jsonb as string-keyed maps.
  defp cell_key(%{"row" => r, "col" => c}), do: {r, c}
  defp cell_key(%{row: r, col: c}), do: {r, c}

  @doc "Display week number for a date, given the schedule's week 1."
  def week_for_date(%Schedule{} = schedule, %Date{} = date) do
    WeekGrid.frost_index(schedule.week_1_start_date, date) + 1
  end
end
