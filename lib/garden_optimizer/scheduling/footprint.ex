defmodule GardenOptimizer.Scheduling.Footprint do
  @moduledoc """
  How much of the grid one plant unit takes up.

  Every 6" x 6" square carries a budget of 36 square inches. A plant is one of two shapes:

    * `{:shared, sq_in}` — needs 36 sq in or less, so it consumes part of a *single* square and
      shares the remainder with other small plants. Four radishes at 9 sq_in fit in one square,
      which is the whole point of square-foot gardening.

    * `{:block, w, h}` — needs more than one square, so it claims a `w x h` rectangle
      exclusively. The rectangle is chosen as close to square as possible, which may round up:
      a plant needing 3 squares takes a 2x2 and wastes one.
  """

  @square_in GardenOptimizer.Gardens.GrowingArea.square_in()
  @square_capacity @square_in * @square_in

  @type t :: {:shared, pos_integer()} | {:block, pos_integer(), pos_integer()}

  @doc "Square inches one 6\" x 6\" square can hold."
  def square_capacity, do: @square_capacity

  @doc """
  Footprint for a plant of `sq_in` square inches.

      iex> Footprint.for_sq_in(9)
      {:shared, 9}
      iex> Footprint.for_sq_in(324)
      {:block, 3, 3}
  """
  @spec for_sq_in(pos_integer()) :: t()
  def for_sq_in(sq_in) when is_integer(sq_in) and sq_in > 0 do
    if sq_in <= @square_capacity do
      {:shared, sq_in}
    else
      squares = ceil_div(sq_in, @square_capacity)
      w = ceil_sqrt(squares)
      {:block, w, ceil_div(squares, w)}
    end
  end

  @doc """
  Square inches this footprint reserves once rounded to whole squares.

  Used for the capacity meter, so the number the user sees reflects what the layout will
  actually consume.
  """
  @spec reserved_sq_in(t()) :: pos_integer()
  def reserved_sq_in({:shared, sq_in}), do: sq_in
  def reserved_sq_in({:block, w, h}), do: w * h * @square_capacity

  @doc "Number of grid squares this footprint touches (a shared plant touches one)."
  @spec square_count(t()) :: pos_integer()
  def square_count({:shared, _}), do: 1
  def square_count({:block, w, h}), do: w * h

  defp ceil_div(a, b), do: div(a + b - 1, b)

  defp ceil_sqrt(n) do
    root = n |> :math.sqrt() |> Float.ceil() |> trunc()
    # Guard against float imprecision at exact squares (e.g. sqrt(49) -> 6.999...).
    if (root - 1) * (root - 1) >= n, do: root - 1, else: root
  end
end
