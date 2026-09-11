defmodule GardenOptimizer.Plants do
  @moduledoc """
  The catalog of plant varieties.

  Plants are shared across gardens: importing a URL once makes that variety available everywhere,
  and re-importing the same URL refreshes it rather than creating a duplicate.
  """

  import Ecto.Query, warn: false

  alias GardenOptimizer.Plants.{Importer, Plant}
  alias GardenOptimizer.Repo

  @doc "Every known plant, alphabetically by common type then variety."
  def list_plants do
    Repo.all(from p in Plant, order_by: [asc: p.common_type, asc: p.variety_name])
  end

  def get_plant!(id), do: Repo.get!(Plant, id)

  def get_plant_by_source_url(url), do: Repo.get_by(Plant, source_url: url)

  def change_plant(%Plant{} = plant, attrs \\ %{}), do: Plant.changeset(plant, attrs)

  def create_plant(attrs) do
    %Plant{}
    |> Plant.changeset(attrs)
    |> Repo.insert()
  end

  def update_plant(%Plant{} = plant, attrs) do
    plant
    |> Plant.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Import a plant from a URL, refreshing the existing row if that URL was imported before.

  Errors carry a reason atom that `Importer.describe_error/1` turns into user-facing copy.
  """
  @spec import_from_url(String.t()) :: {:ok, Plant.t()} | {:error, Importer.error()}
  def import_from_url(url) do
    with {:ok, attrs} <- Importer.extract(url) do
      existing = get_plant_by_source_url(attrs["source_url"]) || %Plant{}

      existing
      |> Plant.changeset(attrs)
      |> Repo.insert_or_update()
      |> case do
        {:ok, plant} -> {:ok, plant}
        {:error, changeset} -> {:error, {:invalid_plant, changeset}}
      end
    end
  end
end
