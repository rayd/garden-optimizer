defmodule GardenOptimizer.Scheduling.Occupancy do
  @moduledoc """
  How full every square is, week by week.

  Each 6" x 6" square carries a 36 square-inch budget per week. Small plants draw down part of
  that budget and share what's left; anything larger than one square takes whole squares
  exclusively. Storage is `%{{area_id, row, col} => %{week_index => used_sq_in}}` — sparse, so an
  untouched square costs nothing and answers "free?" in constant time.
  """

  alias GardenOptimizer.Scheduling.Footprint

  @capacity Footprint.square_capacity()

  @type key :: {term(), non_neg_integer(), non_neg_integer()}
  @type t :: %{optional(key()) => %{optional(integer()) => non_neg_integer()}}

  @doc "An empty grid."
  @spec new() :: t()
  def new, do: %{}

  @doc "Square inches used in one square during one week."
  @spec used(t(), key(), integer()) :: non_neg_integer()
  def used(occupancy, key, week) do
    occupancy |> Map.get(key, %{}) |> Map.get(week, 0)
  end

  @doc "True when the square holds nothing at all that week."
  @spec empty?(t(), key(), integer()) :: boolean()
  def empty?(occupancy, key, week), do: used(occupancy, key, week) == 0

  @doc """
  True when `need` square inches fit in this square for *every* week in `weeks`.

  Passing the full 36 asks whether the square is completely empty throughout, which is what an
  exclusive multi-square plant requires of each of its cells.
  """
  @spec room?(t(), key(), Enumerable.t(), pos_integer()) :: boolean()
  def room?(occupancy, key, weeks, need) do
    case Map.get(occupancy, key) do
      nil -> need <= @capacity
      weekly -> Enum.all?(weeks, &(Map.get(weekly, &1, 0) + need <= @capacity))
    end
  end

  @doc "Largest amount already used in this square across `weeks` (0 if untouched)."
  @spec peak_used(t(), key(), Enumerable.t()) :: non_neg_integer()
  def peak_used(occupancy, key, weeks) do
    case Map.get(occupancy, key) do
      nil -> 0
      weekly -> Enum.reduce(weeks, 0, &max(Map.get(weekly, &1, 0), &2))
    end
  end

  @doc "Charge `need` square inches to each of `keys` for every week in `weeks`."
  @spec occupy(t(), [key()], Enumerable.t(), pos_integer()) :: t()
  def occupy(occupancy, keys, weeks, need) do
    weeks = Enum.to_list(weeks)

    Enum.reduce(keys, occupancy, fn key, acc ->
      Map.update(
        acc,
        key,
        Map.new(weeks, &{&1, need}),
        fn weekly ->
          Enum.reduce(weeks, weekly, &Map.update(&2, &1, need, fn u -> u + need end))
        end
      )
    end)
  end
end
