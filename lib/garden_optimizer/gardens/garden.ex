defmodule GardenOptimizer.Gardens.Garden do
  @moduledoc """
  A garden: a name, the zip code it sits in, and the frost dates that bound its growing season.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias GardenOptimizer.Gardens.{GardenPlant, GrowingArea}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "gardens" do
    field :name, :string
    field :zip_code, :string
    field :last_frost_date, :date
    field :first_frost_date, :date

    # SHA-256 of the visitor token that owns this garden. Set from the caller's scope and
    # deliberately absent from `cast/3` below, so no request body can claim someone else's garden.
    field :visitor_hash, :string

    has_many :growing_areas, GrowingArea, preload_order: [asc: :inserted_at]
    has_many :garden_plants, GardenPlant

    timestamps(type: :utc_datetime)
  end

  def changeset(garden, attrs) do
    garden
    |> cast(attrs, [:name, :zip_code, :last_frost_date, :first_frost_date])
    |> validate_required([:name, :zip_code, :last_frost_date, :first_frost_date])
    |> validate_format(:zip_code, ~r/^\d{5}$/, message: "must be a 5-digit US zip code")
    |> validate_frost_order()
  end

  defp validate_frost_order(changeset) do
    last = get_field(changeset, :last_frost_date)
    first = get_field(changeset, :first_frost_date)

    if last && first && Date.compare(first, last) != :gt do
      add_error(changeset, :first_frost_date, "must fall after the last frost date")
    else
      changeset
    end
  end
end
