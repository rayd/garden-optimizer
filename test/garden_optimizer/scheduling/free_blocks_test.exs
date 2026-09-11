defmodule GardenOptimizer.Scheduling.FreeBlocksTest do
  use ExUnit.Case, async: true

  import GardenOptimizer.Fixtures

  alias GardenOptimizer.Scheduling.{FreeBlocks, Occupancy, WeekGrid}

  @last_frost ~D[2027-03-31]
  @first_frost ~D[2027-11-03]

  # A ten-week season on a single square keeps the arithmetic obvious.
  defp ten_week_grid do
    %WeekGrid{
      last_frost_date: @last_frost,
      first_frost_date: @first_frost,
      start_index: 0,
      end_index: 9
    }
  end

  defp one_square, do: area(rows: 1, cols: 1)

  defp occupy_weeks(area, weeks, used \\ 36) do
    Occupancy.occupy(Occupancy.new(), [{area.id, 0, 0}], weeks, used)
  end

  test "a run shorter than five weeks is not an opportunity" do
    bed = one_square()
    # Weeks 0-5 busy leaves only 6,7,8,9 free — four weeks.
    occupancy = occupy_weeks(bed, 0..5)

    assert FreeBlocks.detect(ten_week_grid(), [bed], occupancy) == []
  end

  test "a run of exactly five weeks counts" do
    bed = one_square()
    occupancy = occupy_weeks(bed, 0..4)

    assert [block] = FreeBlocks.detect(ten_week_grid(), [bed], occupancy)
    assert block.start_index == 5
    assert block.weeks_available == 5
    assert {block.row, block.col} == {0, 0}
  end

  test "a square nothing ever touches is one block spanning the season" do
    bed = one_square()

    assert [block] = FreeBlocks.detect(ten_week_grid(), [bed], Occupancy.new())
    assert block.start_index == 0
    assert block.weeks_available == 10
  end

  test "two gaps separated by an occupied stretch are two blocks" do
    bed = one_square()
    # Weeks 0-4 free, 5-6 busy... that second gap is only 3 weeks, so widen the season instead.
    grid = %{ten_week_grid() | end_index: 15}
    occupancy = occupy_weeks(bed, 5..6)

    blocks = FreeBlocks.detect(grid, [bed], occupancy)

    assert length(blocks) == 2
    assert Enum.map(blocks, &{&1.start_index, &1.weeks_available}) == [{0, 5}, {7, 9}]
  end

  test "a partly-filled shared square is working, not free" do
    bed = one_square()
    # One radish uses 9 of 36 sq in — the square is in use even though it has room.
    occupancy = occupy_weeks(bed, 0..9, 9)

    assert FreeBlocks.detect(ten_week_grid(), [bed], occupancy) == []
  end

  test "blocks are reported per square, across every bed" do
    bed_a = area(rows: 2, cols: 2)
    bed_b = area(rows: 1, cols: 3)

    blocks = FreeBlocks.detect(ten_week_grid(), [bed_a, bed_b], Occupancy.new())

    assert length(blocks) == 7

    assert blocks |> Enum.map(& &1.area_id) |> Enum.frequencies() == %{
             bed_a.id => 4,
             bed_b.id => 3
           }
  end

  test "results are ordered by start week, longest span first" do
    bed = area(rows: 1, cols: 2)

    occupancy =
      Occupancy.new()
      |> Occupancy.occupy([{bed.id, 0, 0}], 0..2, 36)
      |> Occupancy.occupy([{bed.id, 0, 1}], 0..0, 36)

    blocks = FreeBlocks.detect(ten_week_grid(), [bed], occupancy)

    assert Enum.map(blocks, &{&1.start_index, &1.weeks_available}) == [{1, 9}, {3, 7}]
  end
end
