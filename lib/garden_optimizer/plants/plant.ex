defmodule GardenOptimizer.Plants.Plant do
  @moduledoc """
  A plant variety and the horticultural facts the scheduler needs.

  Plants are global rather than per-garden: importing a URL yields one row that any garden can
  reference. `sq_in` is the area a single mature plant needs, derived from its spacing.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @anchors [:last_frost, :first_frost]
  @harvest_types [:once, :continuous]

  schema "plants" do
    field :variety_name, :string
    field :common_type, :string
    field :sq_in, :integer
    field :planting_anchor, Ecto.Enum, values: @anchors
    field :anchor_offset_weeks_min, :integer
    field :anchor_offset_weeks_max, :integer
    field :days_to_maturity, :integer
    field :harvest_type, Ecto.Enum, values: @harvest_types
    field :source_url, :string

    timestamps(type: :utc_datetime)
  end

  @doc "Anchors a `planting_anchor` may take."
  def anchors, do: @anchors

  @doc "Values a `harvest_type` may take."
  def harvest_types, do: @harvest_types

  @castable ~w(variety_name common_type sq_in planting_anchor anchor_offset_weeks_min
               anchor_offset_weeks_max days_to_maturity harvest_type source_url)a

  def changeset(plant, attrs) do
    plant
    |> cast(attrs, @castable)
    |> validate_required(@castable -- [:source_url])
    |> validate_number(:sq_in, greater_than: 0)
    |> validate_number(:days_to_maturity, greater_than: 0)
    |> validate_offset_order()
    |> unique_constraint(:source_url)
  end

  defp validate_offset_order(changeset) do
    min = get_field(changeset, :anchor_offset_weeks_min)
    max = get_field(changeset, :anchor_offset_weeks_max)

    if is_integer(min) and is_integer(max) and min > max do
      add_error(
        changeset,
        :anchor_offset_weeks_max,
        "must be greater than or equal to anchor_offset_weeks_min"
      )
    else
      changeset
    end
  end
end
