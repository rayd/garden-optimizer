# Seeds a realistic garden so the app can be exercised without an ANTHROPIC_API_KEY.
# The frost dates still come from the live API, so garden setup is genuinely end-to-end.
#
#     mix run priv/repo/seeds.exs

alias GardenOptimizer.{Gardens, Plants, Repo, Scheduling}

Repo.delete_all(GardenOptimizer.Gardens.Garden)

{:ok, garden} = Gardens.create_garden(%{"name" => "Backyard beds", "zip_code" => "27516"})
IO.puts("Garden: #{garden.name} — #{garden.last_frost_date} → #{garden.first_frost_date}")

beds =
  List.duplicate({48, 96}, 3) ++ List.duplicate({30, 108}, 2) ++ List.duplicate({48, 48}, 4)

for {{width, length}, i} <- Enum.with_index(beds, 1) do
  {:ok, _} =
    Gardens.add_growing_area(garden, %{
      "name" => "Bed #{i}",
      "width_in" => width,
      "length_in" => length
    })
end

# Values of the shape the importer produces, covering both anchors, both harvest types,
# and both footprint kinds (shared squares and exclusive blocks).
catalog = [
  %{
    variety_name: "Cherokee Purple",
    common_type: "tomato",
    sq_in: 324,
    planting_anchor: :last_frost,
    anchor_offset_weeks_min: 1,
    anchor_offset_weeks_max: 3,
    days_to_maturity: 80,
    harvest_type: :continuous,
    quantity: 9
  },
  %{
    variety_name: "Buttercrunch",
    common_type: "lettuce",
    sq_in: 36,
    planting_anchor: :last_frost,
    anchor_offset_weeks_min: -4,
    anchor_offset_weeks_max: -2,
    days_to_maturity: 55,
    harvest_type: :once,
    quantity: 24
  },
  %{
    variety_name: "Cherry Belle",
    common_type: "radish",
    sq_in: 9,
    planting_anchor: :last_frost,
    anchor_offset_weeks_min: -3,
    anchor_offset_weeks_max: 0,
    days_to_maturity: 25,
    harvest_type: :once,
    quantity: 48
  },
  %{
    variety_name: "Sugar Snap",
    common_type: "pea",
    sq_in: 16,
    planting_anchor: :last_frost,
    anchor_offset_weeks_min: -6,
    anchor_offset_weeks_max: -4,
    days_to_maturity: 62,
    harvest_type: :continuous,
    quantity: 20
  },
  %{
    variety_name: "Lacinato",
    common_type: "kale",
    sq_in: 144,
    planting_anchor: :first_frost,
    anchor_offset_weeks_min: -12,
    anchor_offset_weeks_max: -9,
    days_to_maturity: 60,
    harvest_type: :continuous,
    quantity: 8
  },
  %{
    variety_name: "Provider",
    common_type: "bush bean",
    sq_in: 36,
    planting_anchor: :last_frost,
    anchor_offset_weeks_min: 2,
    anchor_offset_weeks_max: 6,
    days_to_maturity: 50,
    harvest_type: :once,
    quantity: 30
  }
]

for attrs <- catalog do
  {quantity, attrs} = Map.pop!(attrs, :quantity)
  url = "https://seeds.example.com/#{attrs.common_type}/#{attrs.variety_name}"

  plant =
    case Plants.get_plant_by_source_url(url) do
      nil ->
        {:ok, plant} = Plants.create_plant(Map.put(attrs, :source_url, url))
        plant

      plant ->
        plant
    end

  case Gardens.set_plant_quantity(garden, plant, quantity) do
    {:ok, n} -> IO.puts("  #{String.pad_trailing(plant.variety_name, 18)} ×#{n}")
    {:error, reason} -> IO.puts("  #{plant.variety_name}: #{reason}")
  end
end

capacity = Gardens.capacity(garden)
IO.puts("\nSpace: #{capacity.percent_used}% of #{capacity.total_squares} squares")

{:ok, schedule} = Scheduling.build(garden)

IO.puts(
  "Schedule: #{schedule.week_count} weeks, #{length(schedule.assignments)} plantings, " <>
    "#{length(schedule.free_blocks)} free planting blocks"
)

IO.puts("Unplaced: #{inspect(Scheduling.unplaced_details(schedule))}")
IO.puts("\nOpen this garden at: /gardens/#{garden.id}")
