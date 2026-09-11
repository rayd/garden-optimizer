defmodule GardenOptimizer.SchedulingTest do
  use GardenOptimizer.DataCase, async: true

  import GardenOptimizer.Fixtures

  alias GardenOptimizer.{Gardens, Scheduling}
  alias GardenOptimizer.Scheduling.Footprint

  setup do
    garden = garden_fixture()
    bed = growing_area_fixture(garden, name: "Bed 1", width_in: 48, length_in: 96)
    %{garden: garden, bed: bed}
  end

  describe "build/2" do
    test "refuses to build a schedule with nothing to schedule", %{garden: garden} do
      assert {:error, :no_plants} = Scheduling.build(garden)
    end

    test "refuses to build a schedule with nowhere to plant" do
      assert {:error, :no_growing_areas} = Scheduling.build(garden_fixture())
    end

    test "stores one assignment per plant unit", %{garden: garden} do
      tomato = plant_fixture(sq_in: 324, harvest_type: :continuous)
      {:ok, 3} = Gardens.set_plant_quantity(garden, tomato, 3)

      assert {:ok, schedule} = Scheduling.build(garden)
      assert length(schedule.assignments) == 3
      assert schedule.unplaced == %{}
      assert Enum.all?(schedule.assignments, &(length(&1.cells) == 9))
    end

    test "week 1 is the earliest week anything can go in the ground", %{garden: garden} do
      # Peas go in six weeks before the last frost; tomatoes wait for it.
      peas =
        plant_fixture(
          variety_name: "Sugar Snap",
          common_type: "pea",
          sq_in: 36,
          anchor_offset_weeks_min: -6,
          anchor_offset_weeks_max: -4,
          harvest_type: :once,
          days_to_maturity: 60
        )

      tomato = plant_fixture(sq_in: 324, anchor_offset_weeks_min: 0, anchor_offset_weeks_max: 2)

      {:ok, 4} = Gardens.set_plant_quantity(garden, peas, 4)
      {:ok, 2} = Gardens.set_plant_quantity(garden, tomato, 2)

      assert {:ok, schedule} = Scheduling.build(garden)

      assert schedule.week_1_start_date == Date.add(garden.last_frost_date, -6 * 7)
      assert Enum.min(Enum.map(schedule.assignments, & &1.plant_week)) == 1

      # Week 1 falls on the peas' earliest date; the tomatoes come seven weeks later.
      pea_weeks =
        for a <- schedule.assignments, a.garden_plant.plant_id == peas.id, do: a.plant_week

      assert Enum.min(pea_weeks) == 1
    end

    test "planting dates line up with their week numbers", %{garden: garden} do
      plant = plant_fixture(sq_in: 36, anchor_offset_weeks_min: 0, anchor_offset_weeks_max: 0)
      {:ok, 2} = Gardens.set_plant_quantity(garden, plant, 2)

      assert {:ok, schedule} = Scheduling.build(garden)

      for assignment <- schedule.assignments do
        expected = Date.add(schedule.week_1_start_date, (assignment.plant_week - 1) * 7)
        assert assignment.plant_date == expected
      end
    end

    test "a one-time harvester records the date its squares free up", %{garden: garden} do
      # 28 days is exactly four weeks standing after planting.
      radish =
        plant_fixture(
          sq_in: 36,
          harvest_type: :once,
          days_to_maturity: 28,
          anchor_offset_weeks_min: 0,
          anchor_offset_weeks_max: 0
        )

      {:ok, 1} = Gardens.set_plant_quantity(garden, radish, 1)

      assert {:ok, schedule} = Scheduling.build(garden)
      assert [assignment] = schedule.assignments

      assert assignment.last_week == assignment.plant_week + 4
      assert assignment.removal_date == Date.add(assignment.plant_date, 5 * 7)
    end

    test "a continuous harvester holds its squares to the end of the season", %{garden: garden} do
      basil = plant_fixture(sq_in: 36, harvest_type: :continuous)
      {:ok, 1} = Gardens.set_plant_quantity(garden, basil, 1)

      assert {:ok, schedule} = Scheduling.build(garden)
      assert [assignment] = schedule.assignments
      assert assignment.last_week == schedule.week_count
    end

    test "re-building replaces the previous schedule rather than accumulating", %{garden: garden} do
      tomato = plant_fixture(sq_in: 324)
      {:ok, 2} = Gardens.set_plant_quantity(garden, tomato, 2)
      {:ok, first} = Scheduling.build(garden)

      {:ok, 4} = Gardens.set_plant_quantity(garden, tomato, 4)
      {:ok, second} = Scheduling.build(garden)

      refute second.id == first.id
      assert length(second.assignments) == 4
      assert Scheduling.get_schedule(garden).id == second.id
      assert Repo.aggregate(Scheduling.Schedule, :count) == 1
    end

    test "plants that don't fit are reported rather than dropped", %{garden: garden} do
      # The capacity meter is area-based: 128 squares / 9 per tomato says 14 fit. Packing 3x3
      # blocks into a 16x8 grid wastes the last row and the last two columns, so fewer actually
      # do. That gap is exactly what the unplaced report exists to tell the user about.
      tomato = plant_fixture(sq_in: 324, harvest_type: :continuous)
      {:ok, 14} = Gardens.set_plant_quantity(garden, tomato, 14)

      assert {:ok, schedule} = Scheduling.build(garden)

      unplaced = Scheduling.unplaced_details(schedule)
      placed = length(schedule.assignments)

      assert unplaced != []
      assert Enum.all?(unplaced, &(&1.reason =~ "no bed had room"))
      assert placed + Enum.sum(Enum.map(unplaced, & &1.count)) == 14
      # Every unit that *was* placed got a full, non-overlapping 3x3 block.
      assert Enum.all?(schedule.assignments, &(length(&1.cells) == 9))

      assert schedule.assignments |> Enum.flat_map(& &1.cells) |> Enum.uniq() |> length() ==
               placed * 9
    end
  end

  describe "free planting blocks" do
    test "a garden with nothing in it is one long opportunity per square", %{garden: garden} do
      # One radish that clears after four weeks leaves the rest of the bed wide open.
      radish =
        plant_fixture(
          sq_in: 36,
          harvest_type: :once,
          days_to_maturity: 28,
          anchor_offset_weeks_min: 0,
          anchor_offset_weeks_max: 0
        )

      {:ok, 1} = Gardens.set_plant_quantity(garden, radish, 1)

      assert {:ok, schedule} = Scheduling.build(garden)

      # 127 untouched squares each give one season-long block, plus the radish's square,
      # which frees up after it is pulled.
      assert length(schedule.free_blocks) == 128

      season_long =
        Enum.filter(schedule.free_blocks, &(&1.weeks_available == schedule.week_count))

      assert length(season_long) == 127
    end

    test "a square only counts as free when it is completely empty", %{garden: garden} do
      # A single radish occupies a quarter of its square all season long.
      radish = plant_fixture(sq_in: 9, harvest_type: :continuous)
      {:ok, 1} = Gardens.set_plant_quantity(garden, radish, 1)

      assert {:ok, schedule} = Scheduling.build(garden)
      assert length(schedule.free_blocks) == 127
    end

    test "the weekly summary counts blocks and their durations", %{garden: garden} do
      radish =
        plant_fixture(
          sq_in: 36,
          harvest_type: :once,
          days_to_maturity: 28,
          anchor_offset_weeks_min: 0,
          anchor_offset_weeks_max: 0
        )

      {:ok, 2} = Gardens.set_plant_quantity(garden, radish, 2)

      assert {:ok, schedule} = Scheduling.build(garden)

      [%{groups: groups}] = Scheduling.free_squares_by_bed(schedule)
      assert Enum.sum(Enum.map(groups, & &1.count)) == length(schedule.free_blocks)

      # The two radish squares free up together in week 6.
      week_6 = Enum.find(groups, &(&1.start_week == 6))
      assert week_6.count == 2
      assert week_6.weeks_available == schedule.week_count - 5
    end
  end

  describe "to_output/2" do
    test "each cell holds the ids of every plant in that square", %{garden: garden, bed: bed} do
      radish = plant_fixture(sq_in: 9, harvest_type: :continuous)
      {:ok, 4} = Gardens.set_plant_quantity(garden, radish, 4)
      {:ok, schedule} = Scheduling.build(garden)

      %{weeks: [%{week: 1, growing_areas: [area]}]} = Scheduling.to_output(schedule, weeks: [1])

      assert area.id == bed.id
      assert length(area.squares) == 16
      assert Enum.all?(area.squares, &(length(&1) == 8))

      # All four radishes share the first square.
      [[first | rest] | _] = area.squares
      assert length(first) == 4
      assert Enum.all?(rest, &(&1 == []))

      unit_ids = Enum.map(schedule.assignments, & &1.garden_plant_id)
      assert Enum.sort(first) == Enum.sort(unit_ids)
    end

    test "a large plant's id appears in every square of its rectangle", %{garden: garden} do
      tomato = plant_fixture(sq_in: 324, harvest_type: :continuous)
      {:ok, 1} = Gardens.set_plant_quantity(garden, tomato, 1)
      {:ok, schedule} = Scheduling.build(garden)
      [assignment] = schedule.assignments

      %{weeks: [%{growing_areas: [area]}]} = Scheduling.to_output(schedule, weeks: [1])
      occupied = for row <- area.squares, cell <- row, cell != [], do: cell

      assert length(occupied) == 9
      assert Enum.all?(occupied, &(&1 == [assignment.garden_plant_id]))
    end

    test "squares empty out on the week after the plant is pulled", %{garden: garden} do
      radish =
        plant_fixture(
          sq_in: 36,
          harvest_type: :once,
          days_to_maturity: 28,
          anchor_offset_weeks_min: 0,
          anchor_offset_weeks_max: 0
        )

      {:ok, 1} = Gardens.set_plant_quantity(garden, radish, 1)
      {:ok, schedule} = Scheduling.build(garden)

      occupied_cells = fn week ->
        %{weeks: [%{growing_areas: [area]}]} = Scheduling.to_output(schedule, weeks: [week])
        for row <- area.squares, cell <- row, cell != [], do: cell
      end

      assert length(occupied_cells.(1)) == 1
      assert length(occupied_cells.(5)) == 1
      assert occupied_cells.(6) == []
    end

    test "the full output spans every week of the season", %{garden: garden} do
      plant = plant_fixture(sq_in: 36)
      {:ok, 1} = Gardens.set_plant_quantity(garden, plant, 1)
      {:ok, schedule} = Scheduling.build(garden)

      %{weeks: weeks} = Scheduling.to_output(schedule)

      assert length(weeks) == schedule.week_count
      assert Enum.map(weeks, & &1.week) == Enum.to_list(1..schedule.week_count)
      assert List.first(weeks).start_date == schedule.week_1_start_date
    end
  end

  test "the sample garden from the spec schedules end to end", %{garden: garden, bed: bed} do
    # 3 x 4'x8', 2 x 2.5'x9', 4 x 4'x4' — the layout described in the requirements.
    for i <- 2..3, do: growing_area_fixture(garden, name: "Bed #{i}", width_in: 48, length_in: 96)

    for i <- 1..2,
        do: growing_area_fixture(garden, name: "Narrow #{i}", width_in: 30, length_in: 108)

    for i <- 1..4,
        do: growing_area_fixture(garden, name: "Square #{i}", width_in: 48, length_in: 48)

    tomato =
      plant_fixture(
        variety_name: "Cherokee Purple",
        common_type: "tomato",
        sq_in: 324,
        anchor_offset_weeks_min: 0,
        anchor_offset_weeks_max: 2,
        days_to_maturity: 80,
        harvest_type: :continuous
      )

    lettuce =
      plant_fixture(
        variety_name: "Buttercrunch",
        common_type: "lettuce",
        sq_in: 36,
        anchor_offset_weeks_min: -4,
        anchor_offset_weeks_max: -2,
        days_to_maturity: 55,
        harvest_type: :once
      )

    radish =
      plant_fixture(
        variety_name: "Cherry Belle",
        common_type: "radish",
        sq_in: 9,
        anchor_offset_weeks_min: -3,
        anchor_offset_weeks_max: 0,
        days_to_maturity: 25,
        harvest_type: :once
      )

    kale =
      plant_fixture(
        variety_name: "Lacinato",
        common_type: "kale",
        sq_in: 144,
        planting_anchor: :first_frost,
        anchor_offset_weeks_min: -12,
        anchor_offset_weeks_max: -10,
        days_to_maturity: 60,
        harvest_type: :continuous
      )

    {:ok, 12} = Gardens.set_plant_quantity(garden, tomato, 12)
    {:ok, 24} = Gardens.set_plant_quantity(garden, lettuce, 24)
    {:ok, 40} = Gardens.set_plant_quantity(garden, radish, 40)
    {:ok, 8} = Gardens.set_plant_quantity(garden, kale, 8)

    capacity = Gardens.capacity(garden)
    assert capacity.total_squares == 3 * 128 + 2 * 90 + 4 * 64
    assert capacity.percent_used < 100

    assert {:ok, schedule} = Scheduling.build(garden)

    assert schedule.unplaced == %{}
    assert length(schedule.assignments) == 84
    assert schedule.free_blocks != []

    # Radishes consolidate: 40 of them at 9 sq in fit in 10 shared squares.
    radish_cells =
      for a <- schedule.assignments,
          a.garden_plant.plant_id == radish.id,
          cell <- a.cells,
          do: {a.growing_area_id, cell}

    assert length(Enum.uniq(radish_cells)) == 10

    # Nothing may exceed a square's budget: every occupied square in every week stays legal.
    %{weeks: weeks} = Scheduling.to_output(schedule)

    for %{growing_areas: areas} <- weeks,
        %{squares: squares} <- areas,
        row <- squares,
        cell <- row do
      assert length(cell) <= Footprint.square_capacity()
    end

    # The kale is anchored to the fall frost, so it goes in late.
    kale_weeks =
      for a <- schedule.assignments, a.garden_plant.plant_id == kale.id, do: a.plant_week

    lettuce_weeks =
      for a <- schedule.assignments, a.garden_plant.plant_id == lettuce.id, do: a.plant_week

    assert Enum.min(kale_weeks) > Enum.max(lettuce_weeks)

    assert Enum.any?(schedule.assignments, &(&1.growing_area_id == bed.id))
  end
end
