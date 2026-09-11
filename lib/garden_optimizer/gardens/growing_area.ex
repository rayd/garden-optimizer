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
    |> validate_whole_squares(:width_in)
    |> validate_whole_squares(:length_in)
    |> check_constraint(:width_in, name: :whole_squares, message: whole_squares_message())
  end

  # Beds are planned in whole 6" squares, so a dimension that isn't a multiple of 6 has a strip
  # along one edge that can never be planted. Rejecting it up front beats silently swallowing it
  # and then reporting a square count the gardener didn't ask for.
  defp validate_whole_squares(changeset, field) do
    value = get_field(changeset, field)

    if is_integer(value) and value >= @square_in and rem(value, @square_in) != 0 do
      add_error(changeset, field, whole_squares_message(), suggestions: nearest_sizes(value))
    else
      changeset
    end
  end

  defp whole_squares_message, do: ~s(must be a multiple of #{@square_in}")

  @doc """
  The valid bed sizes on either side of `inches`, for pointing at a fix rather than just a rule.

  A tuple rather than a list: it is always exactly two sizes, and a list of small integers would
  inspect as a charlist (`~c"$*"` for `[36, 42]`), which is a confusing thing to hand a caller.

      iex> GrowingArea.nearest_sizes(40)
      {36, 42}
  """
  @spec nearest_sizes(pos_integer()) :: {pos_integer(), pos_integer()}
  def nearest_sizes(inches) do
    lower = max(div(inches, @square_in) * @square_in, @square_in)
    {lower, lower + @square_in}
  end
end
