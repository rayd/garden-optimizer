defmodule GardenOptimizer.Scheduling.WeekGridTest do
  use ExUnit.Case, async: true

  import GardenOptimizer.Fixtures

  alias GardenOptimizer.Scheduling.WeekGrid

  # Chapel Hill, NC (zip 27516) at the 50% probability level.
  @last_frost ~D[2027-03-31]
  @first_frost ~D[2027-11-03]

  describe "frost_index/2" do
    test "the week beginning on the last frost is index 0" do
      assert WeekGrid.frost_index(@last_frost, @last_frost) == 0
      assert WeekGrid.frost_index(@last_frost, ~D[2027-04-06]) == 0
      assert WeekGrid.frost_index(@last_frost, ~D[2027-04-07]) == 1
    end

    test "weeks before the last frost are negative" do
      assert WeekGrid.frost_index(@last_frost, ~D[2027-03-30]) == -1
      assert WeekGrid.frost_index(@last_frost, ~D[2027-03-24]) == -1
      assert WeekGrid.frost_index(@last_frost, ~D[2027-03-23]) == -2
    end
  end

  describe "eligible_range/3" do
    test "last-frost offsets are read straight off the anchor" do
      peas =
        plant(
          planting_anchor: :last_frost,
          anchor_offset_weeks_min: -6,
          anchor_offset_weeks_max: -4
        )

      assert WeekGrid.eligible_range(peas, @last_frost, @first_frost) == {-6, -4}
    end

    test "first-frost offsets are relative to the fall frost" do
      # 31 whole weeks separate the two frost dates.
      kale =
        plant(
          planting_anchor: :first_frost,
          anchor_offset_weeks_min: -10,
          anchor_offset_weeks_max: -8
        )

      assert WeekGrid.eligible_range(kale, @last_frost, @first_frost) == {21, 23}
    end
  end

  describe "new/3" do
    test "week 1 is the earliest week anything could be planted" do
      peas = plant(anchor_offset_weeks_min: -6, anchor_offset_weeks_max: -4)
      tomato = plant(anchor_offset_weeks_min: 0, anchor_offset_weeks_max: 2)

      grid = WeekGrid.new(@last_frost, @first_frost, [tomato, peas])

      assert grid.start_index == -6
      assert WeekGrid.week_1_start_date(grid) == Date.add(@last_frost, -42)
      assert WeekGrid.week_number(grid, -6) == 1
      assert WeekGrid.week_number(grid, 0) == 7
    end

    test "week 1 shifts later when nothing can go in before the last frost" do
      okra = plant(anchor_offset_weeks_min: 3, anchor_offset_weeks_max: 5)
      grid = WeekGrid.new(@last_frost, @first_frost, [okra])

      assert grid.start_index == 3
      assert WeekGrid.week_1_start_date(grid) == Date.add(@last_frost, 21)
    end

    test "an empty garden simply spans last frost to first frost" do
      grid = WeekGrid.new(@last_frost, @first_frost, [])
      assert grid.start_index == 0
      assert grid.end_index == 31
      assert WeekGrid.week_count(grid) == 32
    end

    test "a plant whose window falls past the season cannot invert the grid" do
      too_late =
        plant(
          planting_anchor: :first_frost,
          anchor_offset_weeks_min: 4,
          anchor_offset_weeks_max: 6
        )

      grid = WeekGrid.new(@last_frost, @first_frost, [too_late])

      assert grid.start_index <= grid.end_index
      assert WeekGrid.week_count(grid) >= 1
    end
  end

  describe "last_occupied_index/3" do
    test "a continuous harvester holds its square until first frost" do
      grid = WeekGrid.new(@last_frost, @first_frost, [])
      basil = plant(harvest_type: :continuous, days_to_maturity: 60)

      assert WeekGrid.last_occupied_index(grid, basil, 2) == grid.end_index
    end

    test "a one-time harvester is pulled the week after it matures" do
      grid = WeekGrid.new(@last_frost, @first_frost, [])
      # 28 days to maturity is exactly 4 weeks, so a week-2 planting stands through week 6.
      radish = plant(harvest_type: :once, days_to_maturity: 28)

      assert WeekGrid.last_occupied_index(grid, radish, 2) == 6
    end

    test "a one-time harvester never outlives the season" do
      grid = WeekGrid.new(@last_frost, @first_frost, [])
      squash = plant(harvest_type: :once, days_to_maturity: 400)

      assert WeekGrid.last_occupied_index(grid, squash, 0) == grid.end_index
    end
  end

  test "week numbers and frost indices round-trip" do
    grid = WeekGrid.new(@last_frost, @first_frost, [plant(anchor_offset_weeks_min: -4)])

    for index <- WeekGrid.indices(grid) do
      assert grid |> WeekGrid.week_number(index) |> then(&WeekGrid.index_for_week(grid, &1)) ==
               index
    end
  end
end
