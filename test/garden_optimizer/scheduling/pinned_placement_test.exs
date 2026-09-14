defmodule GardenOptimizer.Scheduling.PinnedPlacementTest do
  @moduledoc """
  Placement of units the gardener has pinned to a bed and a window.
  """
  use ExUnit.Case, async: true

  import GardenOptimizer.Fixtures

  alias GardenOptimizer.Scheduling.{Strategy.EarliestFit, Unit, WeekGrid}

  @last_frost ~D[2027-03-31]
  @first_frost ~D[2027-11-03]

  defp grid(plants), do: WeekGrid.new(@last_frost, @first_frost, plants)

  defp pinned(plant, count, area, range) do
    for _ <- 1..count//1 do
      %Unit{
        id: Ecto.UUID.generate(),
        plant: plant,
        pinned_area_id: area.id,
        pinned_range: range
      }
    end
  end

  describe "a pinned unit" do
    test "goes in its own bed, inside its own window" do
      radish =
        plant(
          sq_in: 36,
          anchor_offset_weeks_min: 0,
          anchor_offset_weeks_max: 30,
          harvest_type: :once,
          days_to_maturity: 25
        )

      bed_a = area(rows: 4, cols: 4)
      bed_b = area(rows: 4, cols: 4)
      units = pinned(radish, 3, bed_b, {12, 16})

      {placements, _occ, unplaced} = EarliestFit.assign(grid([radish]), [bed_a, bed_b], units)

      assert unplaced == %{}
      assert Enum.all?(placements, &(&1.area_id == bed_b.id))
      assert Enum.all?(placements, &(&1.plant_index >= 12 and &1.plant_index <= 16))
    end

    test "takes the earliest week in the window, not the earliest it is eligible" do
      # Eligible from week 0, but pinned to a window opening at 12.
      radish =
        plant(
          sq_in: 36,
          anchor_offset_weeks_min: 0,
          anchor_offset_weeks_max: 30,
          harvest_type: :once,
          days_to_maturity: 25
        )

      bed = area(rows: 4, cols: 4)

      {[placement], _occ, %{}} =
        EarliestFit.assign(grid([radish]), [bed], pinned(radish, 1, bed, {12, 16}))

      assert placement.plant_index == 12
    end

    test "whose window misses its eligible range is reported, not forced in" do
      # Only plantable weeks 0-2; pinned to 12-16.
      pea =
        plant(
          sq_in: 36,
          anchor_offset_weeks_min: 0,
          anchor_offset_weeks_max: 2,
          harvest_type: :once,
          days_to_maturity: 30
        )

      bed = area(rows: 4, cols: 4)
      {[], _occ, unplaced} = EarliestFit.assign(grid([pea]), [bed], pinned(pea, 1, bed, {12, 16}))

      assert unplaced |> Map.values() == [:outside_window]
    end

    test "may stand past the end of its window when nothing reclaims the square" do
      # 60 days is ~8 weeks standing, well past a 4-week window — legal, since the occupancy
      # check is what actually prevents collisions.
      chard =
        plant(
          sq_in: 36,
          anchor_offset_weeks_min: 0,
          anchor_offset_weeks_max: 30,
          harvest_type: :once,
          days_to_maturity: 60
        )

      bed = area(rows: 4, cols: 4)

      {[placement], _occ, %{}} =
        EarliestFit.assign(grid([chard]), [bed], pinned(chard, 1, bed, {12, 15}))

      assert placement.plant_index == 12
      assert placement.last_index > 15
    end
  end

  describe "a unit pinned to squares" do
    defp on_squares(plant, area, range, cells, id \\ Ecto.UUID.generate()) do
      %Unit{
        id: id,
        plant: plant,
        pinned_area_id: area.id,
        pinned_range: range,
        pinned_cells: MapSet.new(cells)
      }
    end

    defp lettuce do
      plant(
        sq_in: 36,
        anchor_offset_weeks_min: 0,
        anchor_offset_weeks_max: 30,
        harvest_type: :once,
        days_to_maturity: 25
      )
    end

    test "takes only squares from its set, even when earlier ones are free" do
      lettuce = lettuce()
      bed = area(rows: 4, cols: 4)
      allowed = [{2, 2}, {3, 3}]
      units = for _ <- 1..2, do: on_squares(lettuce, bed, {12, 16}, allowed)

      {placements, _occ, unplaced} = EarliestFit.assign(grid([lettuce]), [bed], units)

      assert unplaced == %{}
      assert placements |> Enum.flat_map(& &1.cells) |> Enum.sort() == allowed
      assert Enum.all?(placements, &(&1.plant_index == 12))
    end

    test "a multi-square plant needs its whole rectangle inside the set" do
      cabbage =
        plant(
          sq_in: 144,
          anchor_offset_weeks_min: 0,
          anchor_offset_weeks_max: 30,
          harvest_type: :once,
          days_to_maturity: 25
        )

      bed = area(rows: 4, cols: 4)
      g = grid([cabbage])

      # Four squares in a row hold no 2x2.
      in_a_row = [{0, 0}, {0, 1}, {0, 2}, {0, 3}]

      {[], _occ, unplaced} =
        EarliestFit.assign(g, [bed], [on_squares(cabbage, bed, {12, 16}, in_a_row)])

      assert Map.values(unplaced) == [:no_room]

      square = [{2, 2}, {2, 3}, {3, 2}, {3, 3}]

      {[placement], _occ, %{}} =
        EarliestFit.assign(g, [bed], [on_squares(cabbage, bed, {12, 16}, square)])

      assert Enum.sort(placement.cells) == square
    end

    test "whose squares are already taken is reported rather than moved" do
      lettuce = lettuce()

      tomato =
        plant(
          sq_in: 144,
          anchor_offset_weeks_min: 0,
          anchor_offset_weeks_max: 0,
          harvest_type: :continuous
        )

      # The tomato goes in first and holds the top-left 2x2 all season; the rest of the bed is free.
      bed = area(rows: 2, cols: 4)
      units = units(tomato, 1) ++ [on_squares(lettuce, bed, {12, 16}, [{0, 0}])]

      {[placement], _occ, unplaced} = EarliestFit.assign(grid([tomato, lettuce]), [bed], units)

      assert placement.cells |> Enum.sort() == [{0, 0}, {0, 1}, {1, 0}, {1, 1}]
      assert Map.values(unplaced) == [:no_room]
    end

    test "claims its squares before a bed-and-window pin going in the same week" do
      lettuce = lettuce()
      bed = area(rows: 1, cols: 1)

      # Ids chosen so the bed-only pin would win if the tie fell through to id order.
      bed_only = %Unit{id: "a", plant: lettuce, pinned_area_id: bed.id, pinned_range: {12, 12}}
      exact = on_squares(lettuce, bed, {12, 12}, [{0, 0}], "z")

      {[placement], _occ, unplaced} =
        EarliestFit.assign(grid([lettuce]), [bed], [bed_only, exact])

      assert placement.unit_id == "z"
      assert unplaced == %{"a" => :no_room}
    end
  end

  describe "re-solving after a pin is added" do
    setup do
      tomato =
        plant(
          sq_in: 324,
          anchor_offset_weeks_min: 0,
          anchor_offset_weeks_max: 2,
          harvest_type: :continuous
        )

      radish =
        plant(
          sq_in: 36,
          anchor_offset_weeks_min: 0,
          anchor_offset_weeks_max: 4,
          harvest_type: :once,
          days_to_maturity: 25
        )

      bed = area(rows: 16, cols: 8)
      base = units(tomato, 4) ++ units(radish, 6)
      g = grid([tomato, radish])

      {before, _occ, %{}} = EarliestFit.assign(g, [bed], base)
      %{grid: g, bed: bed, base: base, before: before, tomato: tomato, radish: radish}
    end

    test "leaves every pre-existing multi-square placement byte-for-byte identical", ctx do
      # The stability claim the whole re-solve design rests on: pinned units go first and can only
      # take squares that were already free, so nothing established gets displaced.
      late =
        plant(
          sq_in: 144,
          anchor_offset_weeks_min: 0,
          anchor_offset_weeks_max: 30,
          harvest_type: :once,
          days_to_maturity: 25
        )

      extra = pinned(late, 2, ctx.bed, {20, 26})
      {after_, _occ, unplaced} = EarliestFit.assign(ctx.grid, [ctx.bed], ctx.base ++ extra)

      assert unplaced == %{}

      blocks_before = multi_square(ctx.before)
      blocks_after = multi_square(after_) |> Map.take(Map.keys(blocks_before))

      assert blocks_after == blocks_before
    end

    test "does not move any pre-existing unit to a different bed or week", ctx do
      late =
        plant(
          sq_in: 36,
          anchor_offset_weeks_min: 0,
          anchor_offset_weeks_max: 30,
          harvest_type: :once,
          days_to_maturity: 25
        )

      extra = pinned(late, 3, ctx.bed, {20, 26})
      {after_, _occ, %{}} = EarliestFit.assign(ctx.grid, [ctx.bed], ctx.base ++ extra)

      when_and_where = fn placements ->
        Map.new(placements, &{&1.unit_id, {&1.area_id, &1.plant_index, &1.last_index}})
      end

      established = when_and_where.(ctx.before)
      assert when_and_where.(after_) |> Map.take(Map.keys(established)) == established
    end

    test "a unit scheduled later than the pin may still be displaced", ctx do
      # The honest boundary of the stability guarantee. Sorting on the pin-narrowed start protects
      # everything that goes in the ground *before* the pinned unit; plantings that come after it
      # compete for squares as they always have.
      filler =
        plant(
          sq_in: 324,
          anchor_offset_weeks_min: 22,
          anchor_offset_weeks_max: 24,
          harvest_type: :continuous
        )

      base = ctx.base ++ units(filler, 3)
      g = grid([ctx.tomato, ctx.radish, filler])
      {before, _occ, %{}} = EarliestFit.assign(g, [ctx.bed], base)

      late =
        plant(
          sq_in: 324,
          anchor_offset_weeks_min: 0,
          anchor_offset_weeks_max: 30,
          harvest_type: :continuous
        )

      extra = pinned(late, 2, ctx.bed, {20, 21})
      {after_, _occ, _} = EarliestFit.assign(g, [ctx.bed], base ++ extra)

      cells = fn placements ->
        Map.new(placements, &{&1.unit_id, Enum.sort(&1.cells)})
      end

      # Everything planted before week 20 is untouched...
      early_ids = for p <- before, p.plant_index < 20, do: p.unit_id
      assert cells.(after_) |> Map.take(early_ids) == cells.(before) |> Map.take(early_ids)

      # ...while the week-22 filler had to find different squares.
      late_ids = for p <- before, p.plant_index >= 22, do: p.unit_id
      refute cells.(after_) |> Map.take(late_ids) == cells.(before) |> Map.take(late_ids)
    end
  end

  defp multi_square(placements) do
    placements
    |> Enum.filter(&(length(&1.cells) > 1))
    |> Map.new(&{&1.unit_id, {&1.area_id, &1.plant_index, Enum.sort(&1.cells)}})
  end
end
