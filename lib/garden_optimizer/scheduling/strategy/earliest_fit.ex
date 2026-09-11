defmodule GardenOptimizer.Scheduling.Strategy.EarliestFit do
  @moduledoc """
  Greedy earliest-fit placement.

  Units are considered in order of the earliest week they *could* be planted, largest footprint
  first so the awkward shapes get first pick. Each unit takes the first week in its eligible
  window where a home exists, scanning beds in order:

    * a multi-square plant needs a `w x h` rectangle whose every square is completely empty for
      every week it will be standing;
    * a small plant needs one square with room to spare for that whole span, and prefers the
      *fullest* square that still fits, so radishes consolidate into shared squares instead of
      each opening a fresh one.

  A unit with no home anywhere in its window is reported rather than forced in, so the UI can
  say which plants didn't make it and why.
  """

  @behaviour GardenOptimizer.Scheduling.Strategy

  alias GardenOptimizer.Scheduling.{Area, Footprint, Occupancy, Placement, Unit, WeekGrid}

  @capacity Footprint.square_capacity()

  @impl true
  def assign(%WeekGrid{} = grid, areas, units) do
    units
    |> Enum.map(&annotate(&1, grid))
    |> Enum.sort_by(fn %{window: {from, _to}, footprint: fp, unit: unit} ->
      {from, -Footprint.square_count(fp), unit.id}
    end)
    |> Enum.reduce({[], Occupancy.new(), %{}}, fn candidate, {placed, occupancy, unplaced} ->
      case place(candidate, grid, areas, occupancy) do
        {:ok, placement, occupancy} ->
          {[placement | placed], occupancy, unplaced}

        {:error, reason} ->
          {placed, occupancy, Map.put(unplaced, candidate.unit.id, reason)}
      end
    end)
    |> then(fn {placed, occupancy, unplaced} -> {Enum.reverse(placed), occupancy, unplaced} end)
  end

  defp annotate(%Unit{} = unit, grid) do
    %{
      unit: unit,
      footprint: Footprint.for_sq_in(unit.plant.sq_in),
      window: WeekGrid.eligible_range(unit.plant, grid.last_frost_date, grid.first_frost_date)
    }
  end

  defp place(candidate, grid, areas, occupancy) do
    %{unit: unit, footprint: footprint, window: {from, to}} = candidate

    # A plant may only be planted inside its eligible window *and* inside the season.
    from = max(from, grid.start_index)
    to = min(to, grid.end_index)
    areas = candidate_areas(areas, unit)

    cond do
      areas == [] -> {:error, :no_growing_area}
      from > to -> {:error, :outside_season}
      true -> search(unit, footprint, from..to//1, grid, areas, occupancy)
    end
  end

  defp candidate_areas(areas, %Unit{pinned_area_id: nil}), do: areas

  defp candidate_areas(areas, %Unit{pinned_area_id: id}),
    do: Enum.filter(areas, &(&1.id == id))

  defp search(unit, footprint, weeks, grid, areas, occupancy) do
    result =
      Enum.find_value(weeks, fn index ->
        last = WeekGrid.last_occupied_index(grid, unit.plant, index)
        span = Enum.to_list(index..last//1)

        Enum.find_value(areas, fn area ->
          case find_cells(footprint, area, span, occupancy) do
            nil -> nil
            cells -> {index, last, span, area, cells}
          end
        end)
      end)

    case result do
      nil ->
        {:error, :no_room}

      {index, last, span, area, cells} ->
        keys = Enum.map(cells, fn {r, c} -> {area.id, r, c} end)
        need = cell_demand(footprint)

        placement = %Placement{
          unit_id: unit.id,
          area_id: area.id,
          plant_index: index,
          last_index: last,
          cells: cells
        }

        {:ok, placement, Occupancy.occupy(occupancy, keys, span, need)}
    end
  end

  # A shared plant draws its own area from one square; an exclusive block claims each square whole.
  defp cell_demand({:shared, sq_in}), do: sq_in
  defp cell_demand({:block, _w, _h}), do: @capacity

  # Small plant: one square, best fit, so partly-used squares fill up before empty ones open.
  defp find_cells({:shared, sq_in}, %Area{} = area, span, occupancy) do
    area
    |> Area.cells()
    |> Enum.filter(&Occupancy.room?(occupancy, {area.id, elem(&1, 0), elem(&1, 1)}, span, sq_in))
    |> Enum.max_by(
      fn {r, c} -> Occupancy.peak_used(occupancy, {area.id, r, c}, span) end,
      fn -> nil end
    )
    |> List.wrap()
    |> case do
      [] -> nil
      cells -> cells
    end
  end

  # Large plant: the top-left-most w x h rectangle that is completely empty for the whole span.
  defp find_cells({:block, w, h}, %Area{} = area, span, occupancy) do
    Enum.find_value(0..(area.rows - h)//1, fn row ->
      Enum.find_value(0..(area.cols - w)//1, fn col ->
        cells = for r <- row..(row + h - 1)//1, c <- col..(col + w - 1)//1, do: {r, c}

        if Enum.all?(
             cells,
             &Occupancy.room?(occupancy, {area.id, elem(&1, 0), elem(&1, 1)}, span, @capacity)
           ) do
          cells
        end
      end)
    end)
  end
end
