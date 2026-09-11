defmodule GardenOptimizer.Fixtures do
  @moduledoc """
  Builders for test data. Plant attributes default to a plausible tomato and are overridden per
  test, so each test only states the fields it actually cares about.
  """

  alias GardenOptimizer.Gardens
  alias GardenOptimizer.Gardens.GrowingArea
  alias GardenOptimizer.Plants
  alias GardenOptimizer.Plants.Plant
  alias GardenOptimizer.Scheduling.{Area, Unit}

  @doc "An unsaved plant struct — enough for the pure algorithm, which never touches the repo."
  def plant(attrs \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      variety_name: "Cherokee Purple",
      common_type: "tomato",
      sq_in: 324,
      planting_anchor: :last_frost,
      anchor_offset_weeks_min: 0,
      anchor_offset_weeks_max: 2,
      days_to_maturity: 80,
      harvest_type: :continuous
    }

    struct!(Plant, Map.merge(defaults, Map.new(attrs)))
  end

  @doc "A plain grid area, e.g. `area(rows: 16, cols: 8)` for a 4' x 8' bed."
  def area(attrs \\ []) do
    struct!(
      %Area{id: Ecto.UUID.generate(), rows: 16, cols: 8, name: "Bed"},
      Map.new(attrs)
    )
  end

  @doc "`count` placement units of the same plant."
  def units(plant, count, opts \\ []) do
    for _ <- 1..count//1 do
      %Unit{
        id: Ecto.UUID.generate(),
        plant: plant,
        pinned_area_id: Keyword.get(opts, :pinned_area_id)
      }
    end
  end

  ## Persisted fixtures

  def plant_fixture(attrs \\ %{}) do
    {:ok, plant} =
      plant()
      |> Map.from_struct()
      |> Map.drop([:id, :__meta__, :inserted_at, :updated_at])
      |> Map.merge(Map.new(attrs))
      |> Plants.create_plant()

    plant
  end

  def garden_fixture(attrs \\ %{}) do
    {:ok, garden} =
      %{
        "name" => "Backyard",
        "zip_code" => "27516",
        "last_frost_date" => ~D[2027-03-31],
        "first_frost_date" => ~D[2027-11-03]
      }
      |> Map.merge(Map.new(attrs, fn {k, v} -> {to_string(k), v} end))
      |> then(&GardenOptimizer.Gardens.Garden.changeset(%GardenOptimizer.Gardens.Garden{}, &1))
      |> GardenOptimizer.Repo.insert()

    garden
  end

  def growing_area_fixture(garden, attrs \\ %{}) do
    {:ok, area} =
      Gardens.add_growing_area(
        garden,
        Map.merge(
          %{"name" => "Bed 1", "width_in" => 48, "length_in" => 96},
          Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
        )
      )

    area
  end

  @doc "Squares in a persisted bed, for asserting on capacity."
  def squares(%GrowingArea{} = area), do: GrowingArea.squares(area)
end
