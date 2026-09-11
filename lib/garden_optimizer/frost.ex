defmodule GardenOptimizer.Frost do
  @moduledoc """
  Looks up a zip code's average frost dates, which bound a garden's growing season.

  The upstream API reports each frost as a `MM/DD` string with no year, at several probability
  levels; we take the 50% column. Resolving those to real dates means picking the *next* spring
  frost — a garden planned in September is planned for next year's season — and then the fall
  frost that closes that same season.
  """

  require Logger

  @doc """
  Frost dates for the season a gardener planning on `today` would be planning.

  Returns `{:ok, %{last_frost_date: Date.t(), first_frost_date: Date.t()}}`.
  """
  @spec season_dates(String.t(), Date.t()) ::
          {:ok, %{last_frost_date: Date.t(), first_frost_date: Date.t()}}
          | {:error, :zip_not_found | :unavailable}
  def season_dates(zip_code, today \\ Date.utc_today()) do
    with {:ok, %{last: last_md, first: first_md}} <- fetch(zip_code) do
      last_frost_date = next_occurrence(last_md, today)
      # The fall frost that ends the season the spring frost opens, so both sit in one year.
      first_frost_date = in_year(first_md, last_frost_date.year)

      {:ok, %{last_frost_date: last_frost_date, first_frost_date: first_frost_date}}
    end
  end

  defp fetch(zip_code) do
    config = Application.get_env(:garden_optimizer, :frost_api, [])
    url = "#{Keyword.fetch!(config, :base_url)}/frost/#{zip_code}"

    [url: url, receive_timeout: 15_000]
    |> Keyword.merge(Keyword.get(config, :req_options, []))
    |> Req.new()
    |> Req.get()
    |> case do
      {:ok, %Req.Response{status: 200, body: body}} ->
        parse(body)

      {:ok, %Req.Response{status: 404}} ->
        {:error, :zip_not_found}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("frost API returned #{status} for zip #{zip_code}")
        {:error, :unavailable}

      {:error, reason} ->
        Logger.warning("frost API request failed for zip #{zip_code}: #{inspect(reason)}")
        {:error, :unavailable}
    end
  end

  defp parse(%{"data" => %{"frost_dates" => dates}}) do
    with %{"50%" => last} <- Map.get(dates, "last_frost_32f"),
         %{"50%" => first} <- Map.get(dates, "first_frost_32f"),
         {:ok, last_md} <- parse_month_day(last),
         {:ok, first_md} <- parse_month_day(first) do
      {:ok, %{last: last_md, first: first_md}}
    else
      _ -> {:error, :zip_not_found}
    end
  end

  defp parse(_body), do: {:error, :zip_not_found}

  defp parse_month_day(<<month::binary-2, "/", day::binary-2>>) do
    with {month, ""} <- Integer.parse(month),
         {day, ""} <- Integer.parse(day) do
      {:ok, {month, day}}
    else
      _ -> :error
    end
  end

  defp parse_month_day(_), do: :error

  # The next time this month/day comes around, counting today itself.
  defp next_occurrence({month, day}, today) do
    this_year = in_year({month, day}, today.year)

    if Date.compare(this_year, today) == :lt do
      in_year({month, day}, today.year + 1)
    else
      this_year
    end
  end

  # Feb 29 in a common year falls back to Feb 28 rather than blowing up.
  defp in_year({month, day}, year) do
    case Date.new(year, month, day) do
      {:ok, date} -> date
      {:error, :invalid_date} -> Date.new!(year, month, day - 1)
    end
  end
end
