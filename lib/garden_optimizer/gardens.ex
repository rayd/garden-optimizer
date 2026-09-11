defmodule GardenOptimizer.Gardens do
  @moduledoc """
  Gardens, their growing areas, and the plants slated to go in them.

  Quantity lives in row count — one `garden_plant` per plant unit — so the schedule grid can name
  the exact unit in each square. `set_plant_quantity/3` is the only sanctioned way to change it,
  which keeps that representation from leaking into callers.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias GardenOptimizer.Frost
  alias GardenOptimizer.Gardens.{Garden, GardenPlant, GrowingArea}
  alias GardenOptimizer.Plants.Plant
  alias GardenOptimizer.Repo
  alias GardenOptimizer.Scheduling.Footprint

  ## Gardens

  def list_gardens do
    Repo.all(from g in Garden, order_by: [desc: g.inserted_at])
  end

  def get_garden!(id) do
    Repo.get!(Garden, id) |> Repo.preload(:growing_areas)
  end

  def change_garden(%Garden{} = garden, attrs \\ %{}), do: Garden.changeset(garden, attrs)

  @doc """
  Create a garden, resolving its frost dates from the zip code.

  Frost lookup failures surface on the `zip_code` field so the form can show them in place.
  """
  def create_garden(attrs, today \\ Date.utc_today()) do
    attrs = normalize(attrs)

    with {:ok, zip} <- fetch_zip(attrs),
         {:ok, frost} <- lookup_frost(zip, today) do
      %Garden{}
      |> Garden.changeset(Map.merge(attrs, string_keys(frost)))
      |> Repo.insert()
    else
      {:error, :missing_zip} ->
        {:error,
         Garden.changeset(%Garden{}, attrs) |> Ecto.Changeset.apply_action(:insert) |> elem(1)}

      {:error, reason} ->
        {:error,
         %Garden{}
         |> Garden.changeset(attrs)
         |> Ecto.Changeset.add_error(:zip_code, frost_error_message(reason))
         |> Map.put(:action, :insert)}
    end
  end

  def update_garden(%Garden{} = garden, attrs) do
    garden
    |> Garden.changeset(normalize(attrs))
    |> Repo.update()
  end

  def delete_garden(%Garden{} = garden), do: Repo.delete(garden)

  @doc "Frost dates for a zip code, for previewing on the form before saving."
  def preview_frost_dates(zip_code, today \\ Date.utc_today()) do
    lookup_frost(zip_code, today)
  end

  defp fetch_zip(attrs) do
    case attrs |> Map.get("zip_code", "") |> to_string() |> String.trim() do
      "" -> {:error, :missing_zip}
      zip -> {:ok, zip}
    end
  end

  defp lookup_frost(zip, today), do: Frost.season_dates(zip, today)

  defp frost_error_message(:zip_not_found), do: "we don't have frost dates for that zip code"
  defp frost_error_message(_), do: "frost date lookup is unavailable right now"

  defp string_keys(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)

  defp normalize(attrs) when is_map(attrs) do
    Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
  end

  ## Growing areas

  def list_growing_areas(%Garden{id: garden_id}) do
    Repo.all(
      from a in GrowingArea, where: a.garden_id == ^garden_id, order_by: [asc: a.inserted_at]
    )
  end

  def change_growing_area(%GrowingArea{} = area, attrs \\ %{}),
    do: GrowingArea.changeset(area, attrs)

  def add_growing_area(%Garden{} = garden, attrs) do
    %GrowingArea{garden_id: garden.id}
    |> GrowingArea.changeset(attrs)
    |> Repo.insert()
  end

  def get_growing_area!(id), do: Repo.get!(GrowingArea, id)

  def delete_growing_area(%GrowingArea{} = area), do: Repo.delete(area)

  ## Garden plants

  @doc """
  Every known plant paired with how many of it this garden holds.

  Imported plants are catalog-wide, so a plant appears here with a quantity of zero the moment it
  is imported — that is what gives the gardener something to set a quantity *on*. Plants already
  chosen sort first.
  """
  def plant_quantities(%Garden{id: garden_id}) do
    counts =
      Repo.all(
        from gp in GardenPlant,
          where: gp.garden_id == ^garden_id,
          group_by: gp.plant_id,
          select: {gp.plant_id, count(gp.id)}
      )
      |> Map.new()

    Repo.all(from p in Plant, order_by: [asc: p.common_type, asc: p.variety_name])
    |> Enum.map(&{&1, Map.get(counts, &1.id, 0)})
    |> Enum.sort_by(fn {plant, quantity} ->
      {if(quantity > 0, do: 0, else: 1), plant.common_type, plant.variety_name}
    end)
  end

  @doc "Only the plants this garden actually holds, as `{plant, quantity}` pairs."
  def chosen_plant_quantities(%Garden{} = garden) do
    garden |> plant_quantities() |> Enum.filter(fn {_plant, quantity} -> quantity > 0 end)
  end

  @doc "Every plant unit in the garden with its variety preloaded, oldest first."
  def list_garden_plants(%Garden{id: garden_id}) do
    Repo.all(
      from gp in GardenPlant,
        where: gp.garden_id == ^garden_id,
        order_by: [asc: gp.inserted_at, asc: gp.id],
        preload: [:plant]
    )
  end

  @doc """
  Set how many units of `plant` the garden holds, inserting or deleting rows to match.

  Refuses any increase that would push the garden past 100% of its plantable area — the schedule
  can reuse a square across the season, but it cannot put two plants in the same square inch.
  """
  @spec set_plant_quantity(Garden.t(), Plant.t(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, :over_capacity | :no_growing_areas}
  def set_plant_quantity(%Garden{} = garden, %Plant{} = plant, quantity)
      when is_integer(quantity) and quantity >= 0 do
    current = count_plant_units(garden, plant)

    cond do
      quantity == current -> {:ok, quantity}
      quantity < current -> {:ok, remove_units(garden, plant, current - quantity)}
      true -> add_units(garden, plant, quantity - current)
    end
  end

  defp count_plant_units(%Garden{id: garden_id}, %Plant{id: plant_id}) do
    Repo.aggregate(
      from(gp in GardenPlant, where: gp.garden_id == ^garden_id and gp.plant_id == ^plant_id),
      :count
    )
  end

  defp add_units(garden, plant, count) do
    capacity = capacity(garden)
    added_sq_in = count * Footprint.reserved_sq_in(Footprint.for_sq_in(plant.sq_in))

    cond do
      capacity.total_sq_in == 0 -> {:error, :no_growing_areas}
      capacity.used_sq_in + added_sq_in > capacity.total_sq_in -> {:error, :over_capacity}
      true -> {:ok, insert_units(garden, plant, count)}
    end
  end

  defp insert_units(garden, plant, count) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      for _ <- 1..count//1 do
        %{
          id: Ecto.UUID.generate(),
          garden_id: garden.id,
          plant_id: plant.id,
          inserted_at: now,
          updated_at: now
        }
      end

    {_count, _} = Repo.insert_all(GardenPlant, rows)
    count_plant_units(garden, plant)
  end

  # Drop the most recently added units first, so removing what you just added is a clean undo.
  defp remove_units(%Garden{id: garden_id} = garden, %Plant{id: plant_id} = plant, count) do
    doomed =
      Repo.all(
        from gp in GardenPlant,
          where: gp.garden_id == ^garden_id and gp.plant_id == ^plant_id,
          order_by: [desc: gp.inserted_at, desc: gp.id],
          limit: ^count,
          select: gp.id
      )

    Repo.delete_all(from gp in GardenPlant, where: gp.id in ^doomed)
    count_plant_units(garden, plant)
  end

  @doc """
  Reconcile how many units of `plant` are pinned to one free-square group.

  The match is scoped to `origin: :block_fill` and the group's exact bed and window, so filling a
  block never disturbs units the gardener added from the workbench — even of the same plant, in
  the same bed.

  Capacity is *not* checked here; `Scheduling.fill_block/5` has already proven the units fit by
  running the real placer. Area arithmetic would be a weaker and contradictory second opinion.
  """
  @spec set_block_quantity(Garden.t(), Plant.t(), map(), non_neg_integer(), non_neg_integer()) ::
          {:ok, non_neg_integer()}
  def set_block_quantity(%Garden{} = garden, %Plant{} = plant, group, quantity, current) do
    cond do
      quantity == current -> {:ok, quantity}
      quantity > current -> {:ok, insert_block_units(garden, plant, group, quantity - current)}
      true -> {:ok, delete_block_units(garden, plant, group, current - quantity)}
    end
  end

  defp insert_block_units(garden, plant, group, count) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      for _ <- 1..count//1 do
        %{
          id: Ecto.UUID.generate(),
          garden_id: garden.id,
          plant_id: plant.id,
          growing_area_id: group.growing_area_id,
          planting_window_start: group.start_date,
          planting_window_end: group.window_end_date,
          origin: :block_fill,
          inserted_at: now,
          updated_at: now
        }
      end

    {_count, _} = Repo.insert_all(GardenPlant, rows)
    count_block_units(garden, plant, group)
  end

  defp delete_block_units(garden, plant, group, count) do
    doomed =
      garden
      |> block_units_query(plant, group)
      |> order_by([gp], desc: gp.inserted_at, desc: gp.id)
      |> limit(^count)
      |> select([gp], gp.id)
      |> Repo.all()

    Repo.delete_all(from gp in GardenPlant, where: gp.id in ^doomed)
    count_block_units(garden, plant, group)
  end

  @doc "How many units of `plant` are pinned to `group`."
  def count_block_units(%Garden{} = garden, %Plant{} = plant, group) do
    garden |> block_units_query(plant, group) |> Repo.aggregate(:count)
  end

  defp block_units_query(%Garden{id: garden_id}, %Plant{id: plant_id}, group) do
    from gp in GardenPlant,
      where:
        gp.garden_id == ^garden_id and
          gp.plant_id == ^plant_id and
          gp.origin == :block_fill and
          gp.growing_area_id == ^group.growing_area_id and
          gp.planting_window_start == ^group.start_date and
          gp.planting_window_end == ^group.window_end_date
  end

  @doc "Remove every unit of a plant from the garden."
  def remove_plant(%Garden{} = garden, %Plant{} = plant) do
    set_plant_quantity(garden, plant, 0)
  end

  @doc """
  Pin every unit of a plant to a growing area (or unpin with `nil`).
  """
  def pin_plant_to_area(%Garden{id: garden_id}, %Plant{id: plant_id}, growing_area_id) do
    {count, _} =
      Repo.update_all(
        from(gp in GardenPlant, where: gp.garden_id == ^garden_id and gp.plant_id == ^plant_id),
        set: [
          growing_area_id: growing_area_id,
          updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        ]
      )

    {:ok, count}
  end

  ## Capacity

  @doc """
  How much of the garden's plantable area the current plant list claims.

  Both sides of the ratio are measured in whole 6" squares: bed dimensions are floored to whole
  squares, and each plant reserves what it will actually occupy (its own area if it fits inside
  one square and can share it, the full rectangle if it rounds up to several). That keeps the
  meter honest — it can't read 85% on a garden the layout won't fit.
  """
  @spec capacity(Garden.t()) :: %{
          total_squares: non_neg_integer(),
          total_sq_in: non_neg_integer(),
          used_sq_in: non_neg_integer(),
          percent_used: float()
        }
  def capacity(%Garden{} = garden) do
    total_squares =
      garden
      |> list_growing_areas()
      |> Enum.map(&GrowingArea.squares/1)
      |> Enum.sum()

    total_sq_in = total_squares * Footprint.square_capacity()

    used_sq_in =
      Repo.all(
        from gp in GardenPlant,
          join: p in assoc(gp, :plant),
          where: gp.garden_id == ^garden.id,
          group_by: p.sq_in,
          select: {p.sq_in, count(gp.id)}
      )
      |> Enum.map(fn {sq_in, count} ->
        count * Footprint.reserved_sq_in(Footprint.for_sq_in(sq_in))
      end)
      |> Enum.sum()

    %{
      total_squares: total_squares,
      total_sq_in: total_sq_in,
      used_sq_in: used_sq_in,
      percent_used: percent(used_sq_in, total_sq_in)
    }
  end

  defp percent(_used, 0), do: 0.0
  defp percent(used, total), do: Float.round(used * 100 / total, 1)

  @doc "Largest quantity of `plant` the garden could still hold, given what's already in it."
  def max_additional_units(%Garden{} = garden, %Plant{} = plant) do
    capacity = capacity(garden)
    per_unit = Footprint.reserved_sq_in(Footprint.for_sq_in(plant.sq_in))
    max(div(capacity.total_sq_in - capacity.used_sq_in, per_unit), 0)
  end

  @doc false
  def multi_new, do: Multi.new()
end
