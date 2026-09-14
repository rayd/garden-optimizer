defmodule GardenOptimizer.Scheduling.FillBlockTest do
  @moduledoc """
  Filling free planting squares: the grouping the UI lists, and the cap that governs it.
  """
  use GardenOptimizer.DataCase, async: true

  import GardenOptimizer.Fixtures

  alias GardenOptimizer.Gardens
  alias GardenOptimizer.Gardens.GardenPlant
  alias GardenOptimizer.Scheduling

  setup do
    garden = garden_fixture(visitor_scope())
    bed = growing_area_fixture(garden, name: "Bed 1", width_in: 48, length_in: 96)

    # One early one-time crop leaves the rest of the bed open all season, and frees its own
    # squares part-way through — two distinct opportunities to fill.
    radish =
      plant_fixture(
        variety_name: "Cherry Belle",
        common_type: "radish",
        sq_in: 36,
        harvest_type: :once,
        days_to_maturity: 28,
        anchor_offset_weeks_min: 0,
        anchor_offset_weeks_max: 0
      )

    {:ok, 4} = Gardens.set_plant_quantity(garden, radish, 4)
    {:ok, schedule} = Scheduling.build(garden)

    %{garden: garden, bed: bed, radish: radish, schedule: schedule}
  end

  defp group_for(schedule, bed, start_week) do
    schedule
    |> Scheduling.free_squares_by_bed()
    |> Enum.find(&(&1.growing_area.id == bed.id))
    |> Map.fetch!(:groups)
    |> Enum.find(&(&1.start_week == start_week))
  end

  defp block_count(garden, plant, group) do
    garden |> Gardens.list_garden_plants() |> Scheduling.block_unit_count(plant, group)
  end

  defp lettuce_fixture(attrs \\ []) do
    plant_fixture(
      Keyword.merge(
        [
          variety_name: "Buttercrunch",
          sq_in: 36,
          harvest_type: :once,
          days_to_maturity: 35,
          anchor_offset_weeks_min: -4,
          anchor_offset_weeks_max: 30
        ],
        attrs
      )
    )
  end

  # Each unit of `plant` in the schedule mapped to the squares it holds.
  defp cells_by_unit(schedule, plant) do
    for a <- schedule.assignments, a.garden_plant.plant_id == plant.id, into: %{} do
      {a.garden_plant_id, a.cells |> Enum.map(&{&1["row"], &1["col"]}) |> Enum.sort()}
    end
  end

  describe "free_squares_by_bed/1" do
    test "groups squares that open together in the same bed", %{schedule: schedule, bed: bed} do
      [%{growing_area: area, groups: groups}] = Scheduling.free_squares_by_bed(schedule)

      assert area.id == bed.id
      assert Enum.all?(groups, &(&1.count > 0))

      # 124 squares never touched, plus the 4 radish squares freeing up in week 6.
      season_long = Enum.find(groups, &(&1.start_week == 1))
      reclaimed = Enum.find(groups, &(&1.start_week == 6))

      assert season_long.count == 124
      assert reclaimed.count == 4
      assert reclaimed.weeks_available == schedule.week_count - 5
    end

    test "each group names the squares it is made of", %{schedule: schedule, bed: bed} do
      group = group_for(schedule, bed, 6)

      assert length(group.squares) == group.count
      assert group.squares == Enum.sort(group.squares)
    end

    test "the window end is a real date the pin can be stored as", %{schedule: schedule, bed: bed} do
      group = group_for(schedule, bed, 6)

      assert group.window_end_date ==
               Date.add(group.start_date, (group.weeks_available - 1) * 7)
    end

    test "beds with nothing free are left out", %{garden: garden, schedule: schedule} do
      empty = growing_area_fixture(garden, name: "Bed 2", width_in: 48, length_in: 48)

      refute Enum.any?(
               Scheduling.free_squares_by_bed(schedule),
               &(&1.growing_area.id == empty.id)
             )
    end
  end

  describe "plantable_in_group/4" do
    test "offers a crop that finishes in the window and withholds one that can't",
         %{garden: garden, schedule: schedule, bed: bed} do
      group = group_for(schedule, bed, 6)

      quick =
        plant_fixture(
          variety_name: "Quick",
          sq_in: 36,
          harvest_type: :once,
          days_to_maturity: 25,
          anchor_offset_weeks_min: -4,
          anchor_offset_weeks_max: 30
        )

      slow =
        plant_fixture(
          variety_name: "Slow",
          sq_in: 36,
          harvest_type: :once,
          days_to_maturity: 400,
          anchor_offset_weeks_min: -4,
          anchor_offset_weeks_max: 30
        )

      offered =
        Scheduling.plantable_in_group(
          garden,
          Gardens.list_garden_plants(garden),
          group,
          [quick, slow]
        )

      assert Enum.map(offered, & &1.variety_name) == ["Quick"]
    end

    test "a continuous harvester is offered only for a window running to first frost",
         %{garden: garden, schedule: schedule, bed: bed} do
      basil =
        plant_fixture(
          variety_name: "Genovese",
          sq_in: 36,
          harvest_type: :continuous,
          anchor_offset_weeks_min: -4,
          anchor_offset_weeks_max: 30
        )

      garden_plants = Gardens.list_garden_plants(garden)
      to_end = group_for(schedule, bed, 6)

      assert Scheduling.plantable_in_group(garden, garden_plants, to_end, [basil]) == [basil]

      # A window that stops short of the frost cannot take it.
      truncated = %{to_end | weeks_available: 6, window_end_date: Date.add(to_end.start_date, 35)}
      assert Scheduling.plantable_in_group(garden, garden_plants, truncated, [basil]) == []
    end
  end

  describe "fill_block/5" do
    setup %{schedule: schedule, bed: bed} do
      %{group: group_for(schedule, bed, 6)}
    end

    test "plants into the chosen bed inside the chosen window", %{
      garden: garden,
      group: group,
      bed: bed
    } do
      lettuce =
        plant_fixture(
          variety_name: "Buttercrunch",
          sq_in: 36,
          harvest_type: :once,
          days_to_maturity: 35,
          anchor_offset_weeks_min: -4,
          anchor_offset_weeks_max: 30
        )

      assert {:ok, schedule} = Scheduling.fill_block(garden, lettuce, group, 3)

      placed =
        Enum.filter(schedule.assignments, &(&1.garden_plant.plant_id == lettuce.id))

      assert length(placed) == 3
      assert Enum.all?(placed, &(&1.growing_area_id == bed.id))

      # Compared with Date.compare/2, never `>=`: Erlang term order sorts Date structs by their
      # keys alphabetically, so `day` is weighed before `month` and Mar 10 reads as "before" Feb 17.
      assert Enum.all?(placed, fn a ->
               Date.compare(a.plant_date, group.start_date) != :lt and
                 Date.compare(a.plant_date, group.window_end_date) != :gt
             end)
    end

    test "the filled squares stop being reported as free", %{
      garden: garden,
      group: group,
      bed: bed
    } do
      lettuce =
        plant_fixture(
          sq_in: 36,
          harvest_type: :once,
          days_to_maturity: 35,
          anchor_offset_weeks_min: -4,
          anchor_offset_weeks_max: 30
        )

      {:ok, schedule} = Scheduling.fill_block(garden, lettuce, group, 4)
      after_fill = group_for(schedule, bed, 6)

      assert after_fill == nil or after_fill.count < group.count
    end

    test "caps at the area of the squares you clicked, not what the window could absorb",
         %{garden: garden, group: group} do
      # A fast crop could be succession-planted through the window many times over; the cap is the
      # 4 squares the group actually represents.
      lettuce =
        plant_fixture(
          sq_in: 36,
          harvest_type: :once,
          days_to_maturity: 35,
          anchor_offset_weeks_min: -4,
          anchor_offset_weeks_max: 30
        )

      assert Scheduling.block_capacity(group, lettuce, []) == 4
      assert {:ok, _} = Scheduling.fill_block(garden, lettuce, group, 4)
      assert {:error, :no_room} = Scheduling.fill_block(garden, lettuce, group, 5)
    end

    test "small plants share squares, so more of them fit", %{group: group} do
      radish =
        plant_fixture(
          variety_name: "Sparkler",
          sq_in: 9,
          harvest_type: :once,
          days_to_maturity: 25,
          anchor_offset_weeks_min: -4,
          anchor_offset_weeks_max: 30
        )

      # Four to a square across four squares.
      assert Scheduling.block_capacity(group, radish, []) == 16
    end

    test "a plant too big for the group fits none of it", %{group: group} do
      tomato =
        plant_fixture(
          variety_name: "Big",
          sq_in: 324,
          anchor_offset_weeks_min: -4,
          anchor_offset_weeks_max: 30
        )

      # A 3x3 block needs 9 squares; the group has 4.
      assert Scheduling.block_capacity(group, tomato, []) == 0
    end

    test "fills the clicked squares in order, never moving what is already there", %{
      garden: garden,
      group: group
    } do
      lettuce = lettuce_fixture()

      # One at a time, the way the stepper does it — including past a partial fill.
      snapshots =
        for quantity <- 1..4 do
          {:ok, schedule} = Scheduling.fill_block(garden, lettuce, group, quantity)
          cells_by_unit(schedule, lettuce)
        end

      snapshots
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [before, after_] ->
        assert Map.take(after_, Map.keys(before)) == before
      end)

      # Top-left first, and together they end up holding exactly the squares that were clicked.
      assert snapshots |> hd() |> Map.values() == [[hd(group.squares)]]

      assert snapshots |> List.last() |> Map.values() |> Enum.concat() |> Enum.sort() ==
               group.squares
    end

    test "the cap counts other crops already planted into the same squares", %{
      garden: garden,
      group: group
    } do
      lettuce = lettuce_fixture()
      spinach = lettuce_fixture(variety_name: "Bloomsdale")

      {:ok, _} = Scheduling.fill_block(garden, lettuce, group, 3)

      assert Scheduling.block_capacity(group, spinach, Gardens.list_garden_plants(garden)) == 1
      assert {:error, :no_room} = Scheduling.fill_block(garden, spinach, group, 2)
      assert {:ok, schedule} = Scheduling.fill_block(garden, spinach, group, 1)

      taken =
        Map.values(cells_by_unit(schedule, lettuce)) ++
          Map.values(cells_by_unit(schedule, spinach))

      assert taken |> Enum.concat() |> Enum.sort() == group.squares
    end

    test "refuses to overfill, and writes nothing when it does", %{garden: garden, group: group} do
      lettuce =
        plant_fixture(
          sq_in: 36,
          harvest_type: :once,
          days_to_maturity: 35,
          anchor_offset_weeks_min: -4,
          anchor_offset_weeks_max: 30
        )

      before_rows = Repo.aggregate(GardenPlant, :count)
      before_schedule = Scheduling.get_schedule(garden)

      # Far more than the bed could hold in that window.
      assert {:error, :no_room} = Scheduling.fill_block(garden, lettuce, group, 500)

      assert Repo.aggregate(GardenPlant, :count) == before_rows
      assert Scheduling.get_schedule(garden).id == before_schedule.id
    end

    test "lowering a quantity removes only this block's units", %{garden: garden, group: group} do
      lettuce =
        plant_fixture(
          sq_in: 36,
          harvest_type: :once,
          days_to_maturity: 35,
          anchor_offset_weeks_min: -4,
          anchor_offset_weeks_max: 30
        )

      # The same plant also chosen from the workbench, unpinned.
      {:ok, 2} = Gardens.set_plant_quantity(garden, lettuce, 2)
      {:ok, _} = Scheduling.fill_block(garden, lettuce, group, 3)

      assert block_count(garden, lettuce, group) == 3
      assert {:ok, _} = Scheduling.fill_block(garden, lettuce, group, 1)
      assert block_count(garden, lettuce, group) == 1

      # The two workbench units are untouched.
      manual =
        Repo.all(
          from gp in GardenPlant, where: gp.plant_id == ^lettuce.id and gp.origin == :manual
        )

      assert length(manual) == 2
      assert Enum.all?(manual, &is_nil(&1.planting_window_start))
    end

    test "records provenance, the window, and the squares on every row it creates", %{
      garden: garden,
      group: group,
      bed: bed
    } do
      lettuce =
        plant_fixture(
          sq_in: 36,
          harvest_type: :once,
          days_to_maturity: 35,
          anchor_offset_weeks_min: -4,
          anchor_offset_weeks_max: 30
        )

      {:ok, _} = Scheduling.fill_block(garden, lettuce, group, 2)

      rows = Repo.all(from gp in GardenPlant, where: gp.plant_id == ^lettuce.id)

      assert length(rows) == 2

      assert Enum.all?(rows, fn row ->
               row.origin == :block_fill and
                 row.growing_area_id == bed.id and
                 row.planting_window_start == group.start_date and
                 row.planting_window_end == group.window_end_date
             end)

      # One square each, both inside the group, and not the same one.
      cells = Enum.map(rows, fn row -> Enum.map(row.planting_cells, &{&1["row"], &1["col"]}) end)
      assert Enum.all?(cells, &(length(&1) == 1 and hd(&1) in group.squares))
      assert cells |> Enum.uniq() |> length() == 2
    end

    test "the pin survives a plain re-build from the workbench", %{
      garden: garden,
      group: group,
      bed: bed
    } do
      lettuce =
        plant_fixture(
          sq_in: 36,
          harvest_type: :once,
          days_to_maturity: 35,
          anchor_offset_weeks_min: -4,
          anchor_offset_weeks_max: 30
        )

      {:ok, filled} = Scheduling.fill_block(garden, lettuce, group, 3)

      placed_at =
        for a <- filled.assignments, a.garden_plant.plant_id == lettuce.id, do: a.plant_date

      # This is the whole reason the pin is persisted rather than materialized as assignments.
      {:ok, rebuilt} = Scheduling.build(garden)

      after_rebuild =
        for a <- rebuilt.assignments, a.garden_plant.plant_id == lettuce.id, do: a.plant_date

      assert Enum.sort(after_rebuild) == Enum.sort(placed_at)
      assert cells_by_unit(rebuilt, lettuce) == cells_by_unit(filled, lettuce)

      assert Enum.all?(rebuilt.assignments, fn a ->
               a.garden_plant.plant_id != lettuce.id or a.growing_area_id == bed.id
             end)
    end

    test "setting the same quantity is a no-op", %{garden: garden, group: group} do
      lettuce =
        plant_fixture(
          sq_in: 36,
          harvest_type: :once,
          days_to_maturity: 35,
          anchor_offset_weeks_min: -4,
          anchor_offset_weeks_max: 30
        )

      {:ok, _} = Scheduling.fill_block(garden, lettuce, group, 2)
      before = Repo.aggregate(GardenPlant, :count)

      assert {:ok, _} = Scheduling.fill_block(garden, lettuce, group, 2)
      assert Repo.aggregate(GardenPlant, :count) == before
    end
  end
end
