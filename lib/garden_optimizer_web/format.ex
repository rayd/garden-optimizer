defmodule GardenOptimizerWeb.Format do
  @moduledoc """
  Small display helpers shared by every LiveView.

  Dates lead the UI throughout: week numbers shift whenever the plant list changes (week 1 is the
  earliest week anything could be planted), so a calendar date is the stable thing to show.
  """

  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

  @doc ~S'Formats a date as "Mar 31, 2027".'
  def format_date(%Date{} = date) do
    "#{Enum.at(@months, date.month - 1)} #{date.day}, #{date.year}"
  end

  def format_date(nil), do: "—"

  @doc ~S'Formats a date as "Mar 31" — for dense contexts where the year is already obvious.'
  def format_short_date(%Date{} = date), do: "#{Enum.at(@months, date.month - 1)} #{date.day}"
  def format_short_date(nil), do: "—"

  @doc "Pluralizes a count, e.g. `pluralize(1, \"week\")` -> `\"1 week\"`."
  def pluralize(1, word), do: "1 #{word}"
  def pluralize(n, word), do: "#{n} #{word}s"

  @doc """
  A stable colour for a plant, so the same variety reads the same across every week and bed.

  Keyed off the plant id, which means the palette survives re-builds.
  """
  def plant_color(plant_id) do
    palette = [
      %{bg: "bg-emerald-500", soft: "bg-emerald-100 text-emerald-900 border-emerald-300"},
      %{bg: "bg-amber-500", soft: "bg-amber-100 text-amber-900 border-amber-300"},
      %{bg: "bg-sky-500", soft: "bg-sky-100 text-sky-900 border-sky-300"},
      %{bg: "bg-rose-500", soft: "bg-rose-100 text-rose-900 border-rose-300"},
      %{bg: "bg-violet-500", soft: "bg-violet-100 text-violet-900 border-violet-300"},
      %{bg: "bg-lime-600", soft: "bg-lime-100 text-lime-900 border-lime-300"},
      %{bg: "bg-orange-500", soft: "bg-orange-100 text-orange-900 border-orange-300"},
      %{bg: "bg-teal-500", soft: "bg-teal-100 text-teal-900 border-teal-300"}
    ]

    Enum.at(palette, :erlang.phash2(plant_id, length(palette)))
  end
end
