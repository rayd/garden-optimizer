defmodule GardenOptimizer.Scheduling.Strategy.EarliestFitTest do
  use ExUnit.Case, async: true

  import GardenOptimizer.Fixtures

  alias GardenOptimizer.Scheduling.{Footprint, Occupancy, Strategy.EarliestFit, Unit, WeekGrid}

  @last_frost ~D[2027-03-31]
  @first_frost ~D[2027-11-03]
  @capacity Footprint.square_capacity()

  defp grid(plants), do: WeekGrid.new(@last_frost, @first_frost, plants)

  defp assign(plants_with_counts, areas) do
    plants = Enum.flat_map(plants_with_counts, fn {p, n} -> List.duplicate(p, n) end)
    units = Enum.flat_map(plants_with_counts, fn {p, n} -> units(p, n) end)
    {placements, occupancy, unplaced} = EarliestFit.assign(grid(plants), areas, units)
    {grid(plants), placements, occupancy, unplaced}
  end

  describe "sharing squares" do
    test "four radishes fit in one square and the fifth opens another" do
      # 3" x 3" spacing: 9 sq in each, so 36/9 = 4 to a square.
      radish = plant(sq_in: 9, harvest_type: :once, days_to_maturity: 25)
      bed = area(rows: 4, cols: 4)

      {_grid, placements, _occ, unplaced} = assign([{radish, 5}], [bed])

      assert unplaced == %{}
      assert length(placements) == 5

      cells = Enum.map(placements, fn p -> {p.plant_index, hd(p.cells)} end)
      # All five want the same week, so they differ only by square.
      assert placements |> Enum.map(& &1.plant_index) |> Enum.uniq() == [0]

      counts =
        cells |> Enum.map(&elem(&1, 1)) |> Enum.frequencies() |> Map.values() |> Enum.sort()

      assert counts == [1, 4],
             "expected one full square of 4 and one holding the 5th, got #{inspect(counts)}"
    end

    test "a plant that exactly fills a square never shares it" do
      basil = plant(sq_in: 36, harvest_type: :continuous)
      bed = area(rows: 2, cols: 2)

      {_grid, placements, _occ, unplaced} = assign([{basil, 4}], [bed])

      assert unplaced == %{}
      assert placements |> Enum.flat_map(& &1.cells) |> Enum.uniq() |> length() == 4
    end

    test "small plants of different varieties may share the leftover budget" do
      radish = plant(sq_in: 9, common_type: "radish", harvest_type: :once, days_to_maturity: 25)
      carrot = plant(sq_in: 9, common_type: "carrot", harvest_type: :once, days_to_maturity: 25)
      bed = area(rows: 1, cols: 1)

      {_grid, placements, _occ, unplaced} = assign([{radish, 2}, {carrot, 2}], [bed])

      assert unplaced == %{}
      assert length(placements) == 4
      assert placements |> Enum.flat_map(& &1.cells) |> Enum.uniq() == [{0, 0}]
    end
  end

  describe "exclusive blocks" do
    test "a large plant claims whole squares that nothing else may enter" do
      tomato = plant(sq_in: 324, harvest_type: :continuous)
      radish = plant(sq_in: 9, harvest_type: :once, days_to_maturity: 25)
      # 3x3 tomato leaves nothing usable in a 3x3 bed.
      bed = area(rows: 3, cols: 3)

      {_grid, placements, _occ, unplaced} = assign([{tomato, 1}, {radish, 1}], [bed])

      assert length(placements) == 1
      assert map_size(unplaced) == 1
      assert unplaced |> Map.values() |> List.first() == :no_room
    end

    test "a block is laid out as a contiguous rectangle" do
      lettuce = plant(sq_in: 144, harvest_type: :continuous)
      bed = area(rows: 4, cols: 4)

      {_grid, [placement], _occ, %{}} = assign([{lettuce, 1}], [bed])

      rows = placement.cells |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()
      cols = placement.cells |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.sort()

      assert length(placement.cells) == 4
      assert rows == [0, 1]
      assert cols == [0, 1]
    end
  end

  describe "timing" do
    test "every placement sits inside its plant's eligible window" do
      peas =
        plant(
          sq_in: 36,
          anchor_offset_weeks_min: -6,
          anchor_offset_weeks_max: -4,
          harvest_type: :once,
          days_to_maturity: 60
        )

      bed = area(rows: 4, cols: 4)

      {_grid, placements, _occ, %{}} = assign([{peas, 4}], [bed])

      {from, to} = WeekGrid.eligible_range(peas, @last_frost, @first_frost)
      assert Enum.all?(placements, &(&1.plant_index >= from and &1.plant_index <= to))
    end

    test "the earliest eligible week wins when there is room" do
      okra =
        plant(
          sq_in: 36,
          anchor_offset_weeks_min: 3,
          anchor_offset_weeks_max: 6,
          harvest_type: :continuous
        )

      bed = area(rows: 4, cols: 4)

      {_grid, placements, _occ, %{}} = assign([{okra, 2}], [bed])

      assert Enum.all?(placements, &(&1.plant_index == 3))
    end

    test "a plant waits for a later week when the early ones are full" do
      # One square, two units, both one-time harvesters maturing in 2 weeks.
      turnip =
        plant(
          sq_in: 36,
          anchor_offset_weeks_min: 0,
          anchor_offset_weeks_max: 10,
          harvest_type: :once,
          days_to_maturity: 14
        )

      bed = area(rows: 1, cols: 1)

      {_grid, placements, _occ, %{}} = assign([{turnip, 2}], [bed])

      weeks = placements |> Enum.map(& &1.plant_index) |> Enum.sort()
      # First takes weeks 0-2; the second cannot start until week 3.
      assert weeks == [0, 3]
    end
  end

  describe "occupancy invariants" do
    test "no square ever exceeds its 36 sq in budget in any week" do
      radish = plant(sq_in: 9, harvest_type: :once, days_to_maturity: 25)
      lettuce = plant(sq_in: 144, harvest_type: :continuous)
      tomato = plant(sq_in: 324, harvest_type: :continuous)
      beds = [area(rows: 16, cols: 8), area(rows: 8, cols: 8)]

      {grid, _placements, occupancy, _unplaced} =
        assign([{radish, 40}, {lettuce, 6}, {tomato, 4}], beds)

      for {key, weekly} <- occupancy, {week, used} <- weekly do
        assert used <= @capacity,
               "square #{inspect(key)} holds #{used} sq in in week #{week}"
      end

      assert Enum.all?(Map.keys(occupancy), fn {_area, r, c} -> r >= 0 and c >= 0 end)
      assert grid.end_index == 31
    end

    test "a one-time harvester's squares are free again the week after it matures" do
      # 28 days = exactly 4 weeks, so a week-0 planting stands through week 4.
      radish =
        plant(
          sq_in: 36,
          harvest_type: :once,
          days_to_maturity: 28,
          anchor_offset_weeks_min: 0,
          anchor_offset_weeks_max: 0
        )

      bed = area(rows: 1, cols: 1)

      {_grid, [placement], occupancy, %{}} = assign([{radish, 1}], [bed])
      key = {bed.id, 0, 0}

      assert placement.last_index == 4
      assert Occupancy.used(occupancy, key, 4) == 36
      assert Occupancy.empty?(occupancy, key, 5)
    end

    test "a continuous harvester's square never frees up" do
      basil =
        plant(
          sq_in: 36,
          harvest_type: :continuous,
          anchor_offset_weeks_min: 0,
          anchor_offset_weeks_max: 0
        )

      bed = area(rows: 1, cols: 1)

      {grid, [placement], occupancy, %{}} = assign([{basil, 1}], [bed])

      assert placement.last_index == grid.end_index

      assert Enum.all?(
               0..grid.end_index//1,
               &(not Occupancy.empty?(occupancy, {bed.id, 0, 0}, &1))
             )
    end
  end

  describe "constraints and failure" do
    test "a pinned unit goes only in its own bed" do
      tomato = plant(sq_in: 324, harvest_type: :continuous)
      bed_a = area(rows: 6, cols: 6)
      bed_b = area(rows: 6, cols: 6)

      units = units(tomato, 2, pinned_area_id: bed_b.id)
      {placements, _occ, %{}} = EarliestFit.assign(grid([tomato]), [bed_a, bed_b], units)

      assert Enum.all?(placements, &(&1.area_id == bed_b.id))
    end

    test "a unit pinned to a bed that isn't in the garden is reported, not dropped silently" do
      tomato = plant(sq_in: 324)
      bed = area(rows: 6, cols: 6)
      units = [%Unit{id: "orphan", plant: tomato, pinned_area_id: Ecto.UUID.generate()}]

      {[], _occ, unplaced} = EarliestFit.assign(grid([tomato]), [bed], units)

      assert unplaced == %{"orphan" => :no_growing_area}
    end

    test "over-subscribing reports what didn't fit rather than crashing" do
      tomato = plant(sq_in: 324, harvest_type: :continuous)
      bed = area(rows: 3, cols: 3)

      {_grid, placements, _occ, unplaced} = assign([{tomato, 4}], [bed])

      assert length(placements) == 1
      assert map_size(unplaced) == 3
      assert unplaced |> Map.values() |> Enum.uniq() == [:no_room]
    end

    test "a plant whose window falls entirely past the first frost is reported" do
      too_late =
        plant(
          sq_in: 36,
          planting_anchor: :first_frost,
          anchor_offset_weeks_min: 2,
          anchor_offset_weeks_max: 4
        )

      normal = plant(sq_in: 36, anchor_offset_weeks_min: 0, anchor_offset_weeks_max: 0)
      bed = area(rows: 4, cols: 4)

      {_grid, placements, _occ, unplaced} = assign([{normal, 1}, {too_late, 1}], [bed])

      assert length(placements) == 1
      assert unplaced |> Map.values() == [:outside_season]
    end
  end

  test "placement is deterministic across runs" do
    radish = plant(sq_in: 9, harvest_type: :once, days_to_maturity: 25)
    tomato = plant(sq_in: 324, harvest_type: :continuous)
    beds = [area(rows: 8, cols: 4), area(rows: 8, cols: 4)]
    units = units(radish, 10) ++ units(tomato, 2)
    g = grid([radish, tomato])

    {first, _, _} = EarliestFit.assign(g, beds, units)
    {second, _, _} = EarliestFit.assign(g, beds, Enum.shuffle(units))

    assert Enum.sort_by(first, & &1.unit_id) == Enum.sort_by(second, & &1.unit_id)
  end
end
