defmodule GardenOptimizer.Scheduling do
  @moduledoc """
  Builds and stores a garden's planting schedule.

  The algorithm itself is pure — `Strategy.EarliestFit` takes a week grid, a list of beds, and a
  list of plant units and hands back placements plus an occupancy grid. This module is the thin
  layer that loads those inputs from the database, converts frost-relative week indices into
  display week numbers, and writes the result down.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias GardenOptimizer.Gardens
  alias GardenOptimizer.Gardens.{Garden, GardenPlant, GrowingArea}
  alias GardenOptimizer.Plants.Plant
  alias GardenOptimizer.Repo

  alias GardenOptimizer.Scheduling.{
    Area,
    Footprint,
    Assignment,
    FreeBlock,
    FreeBlocks,
    Output,
    Schedule,
    Strategy,
    Unit,
    WeekGrid
  }

  @default_strategy Strategy.EarliestFit

  @doc """
  Generate and store the garden's schedule, replacing any previous one.

  Returns `{:error, :no_growing_areas}` or `{:error, :no_plants}` rather than an empty schedule,
  since neither can produce anything worth showing.
  """
  @spec build(Garden.t(), keyword()) :: {:ok, Schedule.t()} | {:error, atom()}
  def build(%Garden{} = garden, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, @default_strategy)
    growing_areas = Gardens.list_growing_areas(garden)
    garden_plants = Gardens.list_garden_plants(garden)

    cond do
      growing_areas == [] ->
        {:error, :no_growing_areas}

      garden_plants == [] ->
        {:error, :no_plants}

      true ->
        do_build(garden, growing_areas, garden_plants, strategy)
    end
  end

  defp do_build(garden, growing_areas, garden_plants, strategy) do
    areas = Enum.map(growing_areas, &Area.from_schema/1)
    grid = week_grid(garden, garden_plants)
    units = Enum.map(garden_plants, &to_unit(&1, grid))

    {placements, occupancy, unplaced} = strategy.assign(grid, areas, units)
    free_blocks = FreeBlocks.detect(grid, areas, occupancy)

    persist(garden, grid, placements, free_blocks, unplaced)
  end

  @doc """
  The week grid for a garden, given the plants that will go in it.

  Exposed because filling a free block has to reason about weeks before anything is written.
  """
  def week_grid(%Garden{} = garden, garden_plants) do
    WeekGrid.new(
      garden.last_frost_date,
      garden.first_frost_date,
      Enum.map(garden_plants, & &1.plant)
    )
  end

  # A stored pin is a pair of dates; the pure core works in frost-relative week indices.
  defp to_unit(garden_plant, grid) do
    %Unit{
      id: garden_plant.id,
      plant: garden_plant.plant,
      pinned_area_id: garden_plant.growing_area_id,
      pinned_range: pinned_range(garden_plant, grid),
      pinned_cells: pinned_cells(garden_plant)
    }
  end

  defp pinned_cells(%{planting_cells: nil}), do: nil

  defp pinned_cells(%{planting_cells: cells}),
    do: MapSet.new(cells, &{&1["row"], &1["col"]})

  defp cell_map({r, c}), do: %{"row" => r, "col" => c}

  defp pinned_range(%{planting_window_start: nil}, _grid), do: nil

  defp pinned_range(%{planting_window_start: from, planting_window_end: to}, grid) do
    {WeekGrid.frost_index(grid.last_frost_date, from),
     WeekGrid.frost_index(grid.last_frost_date, to)}
  end

  defp persist(garden, grid, placements, free_blocks, unplaced) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    schedule_attrs = %{
      generated_at: now,
      week_1_start_date: WeekGrid.week_1_start_date(grid),
      week_count: WeekGrid.week_count(grid),
      unplaced: Map.new(unplaced, fn {id, reason} -> {id, Atom.to_string(reason)} end)
    }

    Multi.new()
    |> Multi.delete_all(:previous, from(s in Schedule, where: s.garden_id == ^garden.id))
    |> Multi.insert(:schedule, fn _ ->
      %Schedule{garden_id: garden.id}
      |> Schedule.changeset(schedule_attrs)
    end)
    |> Multi.insert_all(:assignments, Assignment, fn %{schedule: schedule} ->
      Enum.map(placements, &assignment_row(&1, schedule, grid, now))
    end)
    |> Multi.insert_all(:free_blocks, FreeBlock, fn %{schedule: schedule} ->
      Enum.map(free_blocks, &free_block_row(&1, schedule, grid))
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{schedule: schedule}} -> {:ok, load_schedule(schedule.id)}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp assignment_row(placement, schedule, grid, now) do
    plant_week = WeekGrid.week_number(grid, placement.plant_index)
    last_week = WeekGrid.week_number(grid, placement.last_index)

    %{
      id: Ecto.UUID.generate(),
      schedule_id: schedule.id,
      garden_plant_id: placement.unit_id,
      growing_area_id: placement.area_id,
      plant_week: plant_week,
      plant_date: WeekGrid.start_date(grid, placement.plant_index),
      last_week: last_week,
      # The square frees up the week *after* the plant's last standing week.
      removal_date: WeekGrid.start_date(grid, placement.last_index + 1),
      cells: Enum.map(placement.cells, &cell_map/1),
      inserted_at: now,
      updated_at: now
    }
  end

  defp free_block_row(block, schedule, grid) do
    %{
      id: Ecto.UUID.generate(),
      schedule_id: schedule.id,
      growing_area_id: block.area_id,
      row: block.row,
      col: block.col,
      start_week: WeekGrid.week_number(grid, block.start_index),
      start_date: WeekGrid.start_date(grid, block.start_index),
      weeks_available: block.weeks_available
    }
  end

  @doc """
  Set how many units of `plant` are planted into one free-square group, and re-solve.

  The cap is enforced by running the real placer in memory first: if any of the new units would
  not land, nothing is written and `{:error, :no_room}` comes back. That is stricter than area
  arithmetic and tells the truth about rectangle packing — 24 free squares will not take two
  tomatoes if no 3x3 of them is contiguous.

  Each new unit is pinned to the exact squares the dry run gave it, not just to the bed, so what the
  gardener fills stays where it went: the next unit takes the next free square, and a re-build puts
  everything back in the same place. The dry run picks those squares from the group's own, so
  nothing lands in some other part of the bed.

  Only rows this feature created in these squares are reconciled, so a stepper here can never
  delete a unit the gardener added from the workbench.
  """
  @spec fill_block(Garden.t(), Plant.t(), map(), non_neg_integer(), keyword()) ::
          {:ok, Schedule.t()} | {:error, atom()}
  def fill_block(%Garden{} = garden, %Plant{} = plant, group, quantity, opts \\ [])
      when is_integer(quantity) and quantity >= 0 do
    strategy = Keyword.get(opts, :strategy, @default_strategy)
    existing = Gardens.list_garden_plants(garden)
    mine = Enum.filter(existing, &block_fill_unit?(&1, plant, group))
    current = length(mine)

    cond do
      quantity == current ->
        {:ok, get_schedule(garden)}

      quantity < current ->
        # Units come back oldest first, so the tail is what was added last — a clean undo.
        doomed = mine |> Enum.take(quantity - current) |> Enum.map(& &1.id)
        Gardens.delete_garden_plants(garden, doomed)
        build(garden)

      quantity > block_capacity(group, plant, existing) ->
        {:error, :no_room}

      true ->
        add_to_block(garden, plant, group, quantity - current, existing, strategy)
    end
  end

  @doc """
  The most units of `plant` that fit in a free-square group, measured against those squares and
  whatever other crops have already been planted into them.

  This is the cap the sidebar enforces, and it is deliberately the *area of the squares you
  clicked* rather than everything the pinned window could absorb. Without it the placer would
  happily succession-plant a fast crop through those squares for the rest of the season — 500
  lettuces into an opportunity described as "4 squares".
  """
  @spec block_capacity(map(), Plant.t(), [GardenPlant.t()]) :: non_neg_integer()
  def block_capacity(group, %Plant{} = plant, garden_plants) do
    taken =
      garden_plants
      |> Enum.filter(&(&1.plant_id != plant.id and in_block?(&1, group)))
      |> Enum.map(&reserved_sq_in(&1.plant))
      |> Enum.sum()

    max(div(group.count * Footprint.square_capacity() - taken, reserved_sq_in(plant)), 0)
  end

  defp reserved_sq_in(plant), do: Footprint.reserved_sq_in(Footprint.for_sq_in(plant.sq_in))

  defp add_to_block(garden, plant, group, added, existing, strategy) do
    areas = garden |> Gardens.list_growing_areas() |> Enum.map(&Area.from_schema/1)
    # Stand-in ids: the dry run only needs to know which units are new.
    new_ids = for _ <- 1..added//1, do: Ecto.UUID.generate()
    prospective = existing ++ Enum.map(new_ids, &prospective_row(&1, garden, plant, group))

    {_placements, _occupancy, already_unplaced} = solve(strategy, garden, areas, existing)
    {placements, _occupancy, unplaced} = solve(strategy, garden, areas, prospective)

    # Refused if anything stops fitting, not just the new units: squares are pinned exactly, so a
    # new unit that took a square some other pinned unit needs would silently evict it.
    if Enum.any?(Map.keys(unplaced), &(not Map.has_key?(already_unplaced, &1))) do
      {:error, :no_room}
    else
      cells = for p <- placements, p.unit_id in new_ids, do: Enum.map(p.cells, &cell_map/1)
      Gardens.insert_block_units(garden, plant, group, cells)
      build(garden)
    end
  end

  defp solve(_strategy, _garden, _areas, []), do: {[], nil, %{}}

  defp solve(strategy, garden, areas, garden_plants) do
    grid = week_grid(garden, garden_plants)
    strategy.assign(grid, areas, Enum.map(garden_plants, &to_unit(&1, grid)))
  end

  # A new unit may take any of the group's squares; which ones it gets is what the dry run decides.
  defp prospective_row(id, garden, plant, group) do
    %GardenPlant{
      id: id,
      garden_id: garden.id,
      plant_id: plant.id,
      plant: plant,
      growing_area_id: group.growing_area_id,
      planting_window_start: group.start_date,
      planting_window_end: group.window_end_date,
      planting_cells: Enum.map(group.squares, &cell_map/1),
      origin: :block_fill
    }
  end

  @doc "How many units of `plant` this feature has already planted into `group`."
  def block_unit_count(garden_plants, %Plant{} = plant, group) do
    Enum.count(garden_plants, &block_fill_unit?(&1, plant, group))
  end

  defp block_fill_unit?(garden_plant, plant, group) do
    garden_plant.plant_id == plant.id and in_block?(garden_plant, group)
  end

  # Planted by this feature, in this window, into squares that all belong to the group. Rows filled
  # before squares were pinned have no cells and are left alone.
  defp in_block?(%GardenPlant{planting_cells: nil}, _group), do: false

  defp in_block?(garden_plant, group) do
    squares = MapSet.new(group.squares)

    garden_plant.origin == :block_fill and
      garden_plant.growing_area_id == group.growing_area_id and
      garden_plant.planting_window_start == group.start_date and
      garden_plant.planting_window_end == group.window_end_date and
      Enum.all?(garden_plant.planting_cells, &MapSet.member?(squares, {&1["row"], &1["col"]}))
  end

  ## Reading

  @doc "The garden's current schedule, fully loaded, or nil if it has never been built."
  def get_schedule(%Garden{id: garden_id}) do
    case Repo.one(from s in Schedule, where: s.garden_id == ^garden_id) do
      nil -> nil
      schedule -> load_schedule(schedule.id)
    end
  end

  defp load_schedule(id) do
    Schedule
    |> Repo.get!(id)
    |> Repo.preload([
      :free_blocks,
      assignments: [garden_plant: :plant]
    ])
  end

  @doc """
  The specified `weeks -> growing_areas -> squares` output for a schedule.

  Pass `weeks: [n]` to build just the week the UI is showing.
  """
  def to_output(%Schedule{} = schedule, opts \\ []) do
    areas =
      Repo.all(
        from a in GrowingArea,
          where: a.garden_id == ^schedule.garden_id,
          order_by: [asc: a.inserted_at]
      )

    Output.build(schedule, areas, opts)
  end

  @doc "Assignments that put a plant in the ground during `week`."
  def planted_in_week(%Schedule{assignments: assignments}, week) do
    Enum.filter(assignments, &(&1.plant_week == week))
  end

  @doc "Assignments whose squares free up at the start of `week`."
  def cleared_in_week(%Schedule{assignments: assignments}, week) do
    Enum.filter(assignments, &(&1.last_week == week - 1))
  end

  @doc "Free planting blocks that begin in `week`."
  def free_blocks_in_week(%Schedule{free_blocks: blocks}, week) do
    Enum.filter(blocks, &(&1.start_week == week))
  end

  @doc """
  Free planting squares grouped into the opportunities a gardener can actually act on.

  Squares in the same bed that open on the same date for the same number of weeks are one entry,
  because filling them is one decision. Ordered by bed, then by the date they open.
  """
  def free_squares_by_bed(%Schedule{} = schedule) do
    beds =
      Repo.all(
        from a in GrowingArea,
          where: a.garden_id == ^schedule.garden_id,
          order_by: [asc: a.inserted_at]
      )

    grouped =
      schedule.free_blocks
      |> Enum.group_by(&{&1.growing_area_id, &1.start_week, &1.weeks_available})
      |> Enum.map(fn {{area_id, start_week, weeks}, squares} ->
        start_date = List.first(squares).start_date

        %{
          growing_area_id: area_id,
          count: length(squares),
          start_week: start_week,
          start_date: start_date,
          weeks_available: weeks,
          squares: squares |> Enum.map(&{&1.row, &1.col}) |> Enum.sort(),
          # Inclusive last week the squares are still free, as a date the pin can be stored as.
          window_end_date: Date.add(start_date, (weeks - 1) * 7)
        }
      end)
      |> Enum.group_by(& &1.growing_area_id)

    beds
    |> Enum.map(fn bed ->
      %{
        growing_area: bed,
        groups: grouped |> Map.get(bed.id, []) |> Enum.sort_by(&{&1.start_week, -&1.count})
      }
    end)
    |> Enum.reject(&(&1.groups == []))
  end

  @doc """
  Which of `plants` could be planted into a free-square group and finish before it closes.

  Delegates the actual rule to `WeekGrid.plantable_in_window?/4`; this just turns the group's
  dates into week indices first.
  """
  def plantable_in_group(%Garden{} = garden, garden_plants, group, plants) do
    grid = week_grid(garden, garden_plants)
    from = WeekGrid.frost_index(grid.last_frost_date, group.start_date)
    to = WeekGrid.frost_index(grid.last_frost_date, group.window_end_date)

    Enum.filter(plants, &WeekGrid.plantable_in_window?(grid, &1, from, to))
  end

  @doc "Plant units the algorithm could not place, with a human-readable reason."
  def unplaced_details(%Schedule{unplaced: unplaced} = schedule) do
    ids = Map.keys(unplaced)

    garden_plants =
      Repo.all(
        from gp in GardenOptimizer.Gardens.GardenPlant,
          where: gp.id in ^ids,
          preload: [:plant]
      )

    garden_plants
    |> Enum.group_by(&{&1.plant.variety_name, Map.get(schedule.unplaced, &1.id)})
    |> Enum.map(fn {{variety, reason}, units} ->
      %{variety_name: variety, count: length(units), reason: describe_reason(reason)}
    end)
    |> Enum.sort_by(& &1.variety_name)
  end

  defp describe_reason("no_room"), do: "no bed had room for it during its planting window"

  defp describe_reason("outside_season"),
    do: "its planting window falls outside the growing season"

  defp describe_reason("outside_window"),
    do: "nothing could be planted in the window it's pinned to"

  defp describe_reason("no_growing_area"), do: "the bed it's pinned to no longer exists"
  defp describe_reason(_), do: "it could not be placed"

  @doc false
  def default_strategy, do: @default_strategy
end
