defmodule GardenOptimizer.Scheduling.WeekGrid do
  @moduledoc """
  Translation between calendar dates, frost-relative week indices, and display week numbers.

  Weeks are 7-day blocks aligned to the garden's last frost date, so *frost index* 0 is the week
  beginning on the last frost date and a plant's eligible window is exactly its
  `anchor_offset_weeks_min..max`.

  Display week 1 is the earliest week any plant in the garden could go in the ground, which may
  be well before the last frost (onions, peas, brassicas). Because that depends on the plant
  list, display week numbers shift when the list changes — the UI therefore leads with dates.
  """

  alias GardenOptimizer.Plants.Plant

  @enforce_keys [:last_frost_date, :first_frost_date, :start_index, :end_index]
  defstruct [:last_frost_date, :first_frost_date, :start_index, :end_index]

  @type t :: %__MODULE__{
          last_frost_date: Date.t(),
          first_frost_date: Date.t(),
          start_index: integer(),
          end_index: integer()
        }

  @doc """
  Build the grid spanning from the earliest eligible planting week across `plants` through the
  first frost. With no plants, the season simply runs last frost -> first frost.
  """
  @spec new(Date.t(), Date.t(), [Plant.t()]) :: t()
  def new(last_frost_date, first_frost_date, plants) do
    end_index = frost_index(last_frost_date, first_frost_date)

    # Display week 1 is the earliest week anything could be planted. Clamped to the first frost
    # so a plant whose whole window falls past the season can't produce an inverted grid; such a
    # unit simply has no week to try and comes back unplaced.
    start_index =
      plants
      |> Enum.map(&elem(eligible_range(&1, last_frost_date, first_frost_date), 0))
      |> Enum.min(fn -> 0 end)
      |> min(end_index)

    %__MODULE__{
      last_frost_date: last_frost_date,
      first_frost_date: first_frost_date,
      start_index: start_index,
      end_index: end_index
    }
  end

  @doc "Frost-relative index of the week containing `date`."
  @spec frost_index(Date.t(), Date.t()) :: integer()
  def frost_index(last_frost_date, date) do
    Integer.floor_div(Date.diff(date, last_frost_date), 7)
  end

  @doc """
  Inclusive `{min, max}` frost-relative week indices in which `plant` may be planted.

  Offsets are relative to whichever frost date the plant is anchored to.
  """
  @spec eligible_range(Plant.t(), Date.t(), Date.t()) :: {integer(), integer()}
  def eligible_range(%Plant{} = plant, last_frost_date, first_frost_date) do
    anchor =
      case plant.planting_anchor do
        :last_frost -> 0
        :first_frost -> frost_index(last_frost_date, first_frost_date)
      end

    {anchor + plant.anchor_offset_weeks_min, anchor + plant.anchor_offset_weeks_max}
  end

  @doc "Every frost index in the schedule, earliest first."
  @spec indices(t()) :: [integer()]
  def indices(%__MODULE__{start_index: s, end_index: e}), do: Enum.to_list(s..e//1)

  @doc "Number of weeks the schedule spans."
  @spec week_count(t()) :: pos_integer()
  def week_count(%__MODULE__{start_index: s, end_index: e}), do: e - s + 1

  @doc "Display week number (1-based) for a frost index."
  @spec week_number(t(), integer()) :: integer()
  def week_number(%__MODULE__{start_index: s}, index), do: index - s + 1

  @doc "Frost index for a 1-based display week number."
  @spec index_for_week(t(), integer()) :: integer()
  def index_for_week(%__MODULE__{start_index: s}, week), do: week + s - 1

  @doc "Date on which a given frost index's week begins."
  @spec start_date(t(), integer()) :: Date.t()
  def start_date(%__MODULE__{last_frost_date: lf}, index), do: Date.add(lf, index * 7)

  @doc "Date on which display week 1 begins."
  @spec week_1_start_date(t()) :: Date.t()
  def week_1_start_date(%__MODULE__{} = grid), do: start_date(grid, grid.start_index)

  @doc """
  Can this plant be planted *and* finish inside `from_index..to_index`?

  This is what decides which plants a free planting block is offered. The plant has to be
  plantable somewhere in the window, and whatever it occupies has to be out again by the end of
  it — a window that ends early does so because something else reclaims those squares.

  Continuous harvesters fall out of this on their own: they hold their square until first frost,
  so they only pass for a window that runs to the end of the season.
  """
  @spec plantable_in_window?(t(), Plant.t(), integer(), integer()) :: boolean()
  def plantable_in_window?(%__MODULE__{} = grid, %Plant{} = plant, from_index, to_index) do
    {eligible_from, eligible_to} =
      eligible_range(plant, grid.last_frost_date, grid.first_frost_date)

    earliest = max(eligible_from, from_index)
    latest = min(eligible_to, to_index)

    # Planting as early as the window allows also clears as early as possible, so if the earliest
    # option does not finish in time, nothing later will either.
    earliest <= latest and clears_by(grid, plant, earliest) <= to_index
  end

  # Deliberately *not* `last_occupied_index/3`: that clamps to the end of the season because a
  # plant cannot occupy squares past it, which would make a crop needing 400 days look like it
  # finishes on the last week. Here we are asking whether it matures at all, so it goes unclamped.
  defp clears_by(%__MODULE__{end_index: e}, %Plant{harvest_type: :continuous}, _index), do: e

  defp clears_by(_grid, %Plant{} = plant, index),
    do: index + Integer.floor_div(plant.days_to_maturity, 7)

  @doc """
  Last frost index at which a unit planted at `plant_index` still occupies its squares.

  Continuous harvesters hold their ground until first frost. One-time harvesters are pulled the
  week after they mature.
  """
  @spec last_occupied_index(t(), Plant.t(), integer()) :: integer()
  def last_occupied_index(%__MODULE__{end_index: e}, %Plant{harvest_type: :continuous}, _index),
    do: e

  def last_occupied_index(%__MODULE__{end_index: e}, %Plant{} = plant, plant_index) do
    min(plant_index + Integer.floor_div(plant.days_to_maturity, 7), e)
  end
end
