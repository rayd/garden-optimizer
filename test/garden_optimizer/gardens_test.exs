defmodule GardenOptimizer.GardensTest do
  use GardenOptimizer.DataCase, async: true

  import GardenOptimizer.Fixtures

  alias GardenOptimizer.Gardens

  @recorded File.read!("test/support/fixtures/frost_27516.json")

  defp stub_frost(body \\ @recorded, status \\ 200) do
    Req.Test.stub(GardenOptimizer.FrostStub, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(status, body)
    end)
  end

  describe "create_garden/2" do
    test "resolves frost dates from the zip code" do
      stub_frost()

      assert {:ok, garden} =
               Gardens.create_garden(
                 %{"name" => "Backyard", "zip_code" => "27516"},
                 ~D[2026-09-10]
               )

      assert garden.last_frost_date == ~D[2027-03-31]
      assert garden.first_frost_date == ~D[2027-11-03]
    end

    test "an unknown zip fails on the zip field, where the form can show it" do
      stub_frost(~s({}), 404)

      assert {:error, changeset} =
               Gardens.create_garden(
                 %{"name" => "Backyard", "zip_code" => "00000"},
                 ~D[2026-09-10]
               )

      assert errors_on(changeset).zip_code == ["we don't have frost dates for that zip code"]
    end

    test "an outage says so rather than blaming the zip code" do
      stub_frost(~s({}), 500)

      assert {:error, changeset} =
               Gardens.create_garden(
                 %{"name" => "Backyard", "zip_code" => "27516"},
                 ~D[2026-09-10]
               )

      assert errors_on(changeset).zip_code == ["frost date lookup is unavailable right now"]
    end

    test "a blank zip is a validation error, not a lookup" do
      assert {:error, changeset} =
               Gardens.create_garden(%{"name" => "Backyard", "zip_code" => ""})

      assert errors_on(changeset).zip_code != []
    end
  end

  describe "growing areas" do
    test "a bed is divided into whole 6-inch squares" do
      garden = garden_fixture()
      area = growing_area_fixture(garden, name: "Bed 1", width_in: 48, length_in: 96)

      # 4' x 8' -> 8 columns x 16 rows.
      assert squares(area) == 128
    end

    test "dimensions that aren't a multiple of 6 floor to whole squares" do
      garden = garden_fixture()
      # 2.5' x 9' is exactly 5 x 18, but 40" would waste the last 4".
      assert squares(growing_area_fixture(garden, width_in: 30, length_in: 108)) == 90
      assert squares(growing_area_fixture(garden, width_in: 40, length_in: 40)) == 36
    end
  end

  describe "set_plant_quantity/3" do
    setup do
      garden = garden_fixture()
      growing_area_fixture(garden, width_in: 48, length_in: 96)
      %{garden: garden, plant: plant_fixture(sq_in: 324)}
    end

    test "creates one row per unit and reconciles both directions", %{
      garden: garden,
      plant: plant
    } do
      assert {:ok, 5} = Gardens.set_plant_quantity(garden, plant, 5)
      assert length(Gardens.list_garden_plants(garden)) == 5

      assert {:ok, 2} = Gardens.set_plant_quantity(garden, plant, 2)
      assert length(Gardens.list_garden_plants(garden)) == 2

      assert {:ok, 0} = Gardens.set_plant_quantity(garden, plant, 0)
      assert Gardens.list_garden_plants(garden) == []
    end

    test "setting the same quantity is a no-op", %{garden: garden, plant: plant} do
      {:ok, 3} = Gardens.set_plant_quantity(garden, plant, 3)
      ids = Gardens.list_garden_plants(garden) |> Enum.map(& &1.id) |> Enum.sort()

      assert {:ok, 3} = Gardens.set_plant_quantity(garden, plant, 3)
      assert Gardens.list_garden_plants(garden) |> Enum.map(& &1.id) |> Enum.sort() == ids
    end

    test "refuses to exceed the garden's plantable area", %{garden: garden, plant: plant} do
      # 128 squares / 9 squares per tomato = 14 tomatoes.
      assert {:ok, 14} = Gardens.set_plant_quantity(garden, plant, 14)
      assert {:error, :over_capacity} = Gardens.set_plant_quantity(garden, plant, 15)
      assert length(Gardens.list_garden_plants(garden)) == 14
    end

    test "a garden with no beds can't hold anything yet", %{plant: plant} do
      assert {:error, :no_growing_areas} =
               Gardens.set_plant_quantity(garden_fixture(), plant, 1)
    end

    test "the catalog lists every plant, chosen ones first", %{garden: garden, plant: plant} do
      lettuce = plant_fixture(variety_name: "Buttercrunch", common_type: "lettuce", sq_in: 36)
      unused = plant_fixture(variety_name: "Detroit Red", common_type: "beet", sq_in: 16)
      {:ok, 3} = Gardens.set_plant_quantity(garden, plant, 3)
      {:ok, 8} = Gardens.set_plant_quantity(garden, lettuce, 8)

      # A plant with no units still appears, so there is something to set a quantity on after
      # importing it — but it sorts below the ones already chosen.
      assert [{^lettuce, 8}, {^plant, 3}, {^unused, 0}] = Gardens.plant_quantities(garden)
      assert [{^lettuce, 8}, {^plant, 3}] = Gardens.chosen_plant_quantities(garden)
    end

    test "a plant chosen in another garden shows here with a quantity of zero", %{plant: plant} do
      other = garden_fixture(name: "Front yard")
      growing_area_fixture(other, width_in: 48, length_in: 96)
      {:ok, 2} = Gardens.set_plant_quantity(other, plant, 2)

      assert [{^plant, 0}] = Gardens.plant_quantities(garden_fixture(name: "Empty"))
    end
  end

  describe "capacity/1" do
    setup do
      garden = garden_fixture()
      growing_area_fixture(garden, width_in: 48, length_in: 96)
      %{garden: garden}
    end

    test "an empty garden is 0%", %{garden: garden} do
      capacity = Gardens.capacity(garden)
      assert capacity.total_squares == 128
      assert capacity.total_sq_in == 128 * 36
      assert capacity.percent_used == 0.0
    end

    test "a small plant costs only its own area, not a whole square", %{garden: garden} do
      radish = plant_fixture(variety_name: "Cherry Belle", common_type: "radish", sq_in: 9)
      {:ok, 4} = Gardens.set_plant_quantity(garden, radish, 4)

      # Four radishes share one square: 36 of 4608 sq in.
      assert Gardens.capacity(garden).used_sq_in == 36
    end

    test "a large plant pays for every square its rectangle touches", %{garden: garden} do
      # 3 squares' worth of area rounds up to a 2x2 block, so it reserves four squares.
      awkward = plant_fixture(sq_in: 3 * 36)
      {:ok, 1} = Gardens.set_plant_quantity(garden, awkward, 1)

      assert Gardens.capacity(garden).used_sq_in == 4 * 36
    end

    test "reports how many more of a plant would still fit", %{garden: garden} do
      tomato = plant_fixture(sq_in: 324)
      assert Gardens.max_additional_units(garden, tomato) == 14

      {:ok, 10} = Gardens.set_plant_quantity(garden, tomato, 10)
      assert Gardens.max_additional_units(garden, tomato) == 4
    end
  end

  test "pinning a plant sets the constraint on every one of its units" do
    garden = garden_fixture()
    bed = growing_area_fixture(garden)
    plant = plant_fixture(sq_in: 36)
    {:ok, 3} = Gardens.set_plant_quantity(garden, plant, 3)

    assert {:ok, 3} = Gardens.pin_plant_to_area(garden, plant, bed.id)
    assert Enum.all?(Gardens.list_garden_plants(garden), &(&1.growing_area_id == bed.id))

    assert {:ok, 3} = Gardens.pin_plant_to_area(garden, plant, nil)
    assert Enum.all?(Gardens.list_garden_plants(garden), &is_nil(&1.growing_area_id))
  end
end
