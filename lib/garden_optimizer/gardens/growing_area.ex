defmodule GardenOptimizer.Gardens.GrowingArea do
  @moduledoc """
  A raised bed or other growing area, measured in inches and divided into 6" x 6" squares.

  Dimensions that are not a whole multiple of 6" are floored: a 40"-wide bed yields 6 usable
  columns and the leftover 4" is unplantable.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias GardenOptimizer.Gardens.Garden

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @square_in 6

  schema "growing_areas" do
    field :name, :string
    field :width_in, :integer
    field :length_in, :integer

    belongs_to :garden, Garden

    timestamps(type: :utc_datetime)
  end

  @doc "Side of one planting square, in inches."
  def square_in, do: @square_in

  @doc "Number of whole 6\" columns across the bed's width."
  def cols(%__MODULE__{width_in: w}), do: div(w, @square_in)

  @doc "Number of whole 6\" rows along the bed's length."
  def rows(%__MODULE__{length_in: l}), do: div(l, @square_in)

  @doc "Total plantable squares, ignoring any remainder narrower than 6\"."
  def squares(%__MODULE__{} = area), do: rows(area) * cols(area)

  def changeset(area, attrs) do
    area
    |> cast(attrs, [:name, :width_in, :length_in])
    |> validate_required([:name, :width_in, :length_in])
    |> validate_number(:width_in, greater_than_or_equal_to: @square_in)
    |> validate_number(:length_in, greater_than_or_equal_to: @square_in)
  end

end
