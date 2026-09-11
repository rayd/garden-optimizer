defmodule GardenOptimizer.Scheduling.WindowTest do
  @moduledoc """
  The rule that decides which plants a free planting block is offered.
  """
  use ExUnit.Case, async: true

  import GardenOptimizer.Fixtures

  alias GardenOptimizer.Scheduling.WeekGrid

  @last_frost ~D[2027-03-31]
  @first_frost ~D[2027-11-03]

  # Season runs frost index 0..31; a wide-open eligible range keeps each test about the window.
  defp grid, do: WeekGrid.new(@last_frost, @first_frost, [])

  defp anytime(attrs),
    do: plant(Keyword.merge([anchor_offset_weeks_min: -8, anchor_offset_weeks_max: 30], attrs))

  describe "plantable_in_window?/4" do
    test "a fast one-time crop fits a five-week window" do
      # 25 days is 3 whole weeks standing, so a week-10 planting clears by week 13.
      radish = anytime(harvest_type: :once, days_to_maturity: 25)
      assert WeekGrid.plantable_in_window?(grid(), radish, 10, 14)
    end

    test "a slow one-time crop does not" do
      tomato = anytime(harvest_type: :once, days_to_maturity: 80)
      refute WeekGrid.plantable_in_window?(grid(), tomato, 10, 14)
    end

    test "the boundary is inclusive — clearing on the window's last week still counts" do
      # 28 days is exactly 4 weeks, so week 10 -> still standing week 14, out at 15.
      turnip = anytime(harvest_type: :once, days_to_maturity: 28)
      assert WeekGrid.plantable_in_window?(grid(), turnip, 10, 14)
      refute WeekGrid.plantable_in_window?(grid(), turnip, 10, 13)
    end

    test "a continuous harvester only fits a window that runs to first frost" do
      basil = anytime(harvest_type: :continuous, days_to_maturity: 30)
      g = grid()

      # It holds its square until frost, so any window something else reclaims is out.
      refute WeekGrid.plantable_in_window?(g, basil, 10, 20)
      assert WeekGrid.plantable_in_window?(g, basil, 10, g.end_index)
    end

    test "a plant whose planting window misses the block entirely is rejected" do
      # Only plantable weeks 0-2; the block opens at 10.
      pea =
        plant(
          anchor_offset_weeks_min: 0,
          anchor_offset_weeks_max: 2,
          harvest_type: :once,
          days_to_maturity: 20
        )

      refute WeekGrid.plantable_in_window?(grid(), pea, 10, 20)
    end

    test "a partial overlap counts, as long as it can still finish" do
      # Plantable weeks 8-12; block is 10-20. Planting at 10 clears by 13.
      bean =
        plant(
          anchor_offset_weeks_min: 8,
          anchor_offset_weeks_max: 12,
          harvest_type: :once,
          days_to_maturity: 21
        )

      assert WeekGrid.plantable_in_window?(grid(), bean, 10, 20)
    end

    test "an inverted window is never plantable" do
      radish = anytime(harvest_type: :once, days_to_maturity: 25)
      refute WeekGrid.plantable_in_window?(grid(), radish, 20, 10)
    end

    test "a first-frost anchored plant is measured against the same window" do
      # Eligible 10-8 weeks before first frost, i.e. indices 21-23.
      kale =
        plant(
          planting_anchor: :first_frost,
          anchor_offset_weeks_min: -10,
          anchor_offset_weeks_max: -8,
          harvest_type: :once,
          days_to_maturity: 35
        )

      assert WeekGrid.plantable_in_window?(grid(), kale, 20, 31)
      refute WeekGrid.plantable_in_window?(grid(), kale, 5, 15)
    end
  end
end
