defmodule GardenOptimizer.Scheduling.FootprintTest do
  use ExUnit.Case, async: true

  alias GardenOptimizer.Scheduling.Footprint

  describe "for_sq_in/1" do
    test "plants that fit inside one square share it" do
      # A 3" x 3" radish uses a quarter of a square's 36 sq in budget.
      assert Footprint.for_sq_in(9) == {:shared, 9}
      # A 6" x 6" plant fills a square exactly, leaving nothing to share.
      assert Footprint.for_sq_in(36) == {:shared, 36}
      assert Footprint.for_sq_in(1) == {:shared, 1}
    end

    test "larger plants claim a rectangle of whole squares" do
      # 12" x 12" lettuce -> 4 squares -> 2x2.
      assert Footprint.for_sq_in(144) == {:block, 2, 2}
      # 18" x 18" tomato -> 9 squares -> 3x3.
      assert Footprint.for_sq_in(324) == {:block, 3, 3}
      # 37 sq in barely spills over one square.
      assert Footprint.for_sq_in(37) == {:block, 2, 1}
    end

    test "rectangles are as square as possible, rounding up when they must" do
      assert Footprint.for_sq_in(200) == {:block, 3, 2}
      # 3 squares has no exact rectangle, so it takes a 2x2 and wastes one square.
      assert Footprint.for_sq_in(3 * 36) == {:block, 2, 2}
    end

    test "exact perfect squares do not round up through float imprecision" do
      for n <- [4, 9, 16, 25, 36, 49, 64, 81, 100] do
        assert {:block, w, h} = Footprint.for_sq_in(n * 36)

        assert w == h,
               "#{n} squares should be a #{trunc(:math.sqrt(n))}-a-side block, got #{w}x#{h}"

        assert w * h == n
      end
    end
  end

  describe "reserved_sq_in/1" do
    test "a shared plant reserves only its own area" do
      assert Footprint.reserved_sq_in({:shared, 9}) == 9
    end

    test "a block reserves every square it touches, including any it wastes" do
      assert Footprint.reserved_sq_in({:block, 3, 3}) == 324
      # The 3-square plant that rounded up to 2x2 pays for all four squares.
      assert Footprint.reserved_sq_in({:block, 2, 2}) == 144
    end
  end

  test "square_count/1 counts the squares touched" do
    assert Footprint.square_count({:shared, 9}) == 1
    assert Footprint.square_count({:block, 3, 2}) == 6
  end
end
