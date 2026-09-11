defmodule GardenOptimizer.Plants.Importer do
  @moduledoc """
  Turns a plant page URL into a `Plant` row.

  We fetch and strip the page ourselves and hand Claude the text, rather than asking the model to
  fetch it: the request stays deterministic and testable with a fixture, and a failure to reach
  the page is distinguishable from a failure to understand it. Claude's job is purely extraction,
  constrained by a JSON schema so the response is always shaped correctly.
  """

  require Logger

  alias GardenOptimizer.Plants.Plant

  @anthropic_version "2023-06-01"
  # Enough of a seed-catalog page to cover the culture notes without paying for boilerplate.
  @max_page_chars 40_000
  @strip_selectors ~w(script style noscript nav footer header svg iframe)

  @schema %{
    "type" => "object",
    "properties" => %{
      "variety_name" => %{"type" => "string"},
      "common_type" => %{"type" => "string"},
      "sq_in" => %{"type" => "integer"},
      "planting_anchor" => %{"type" => "string", "enum" => ["last_frost", "first_frost"]},
      "anchor_offset_weeks_min" => %{"type" => "integer"},
      "anchor_offset_weeks_max" => %{"type" => "integer"},
      "days_to_maturity" => %{"type" => "integer"},
      "harvest_type" => %{"type" => "string", "enum" => ["once", "continuous"]}
    },
    "required" => [
      "variety_name",
      "common_type",
      "sq_in",
      "planting_anchor",
      "anchor_offset_weeks_min",
      "anchor_offset_weeks_max",
      "days_to_maturity",
      "harvest_type"
    ],
    "additionalProperties" => false
  }

  @type error ::
          :missing_api_key
          | :invalid_url
          | :page_unavailable
          | :extraction_failed
          | {:invalid_plant, Ecto.Changeset.t()}

  @doc """
  Fetch `url`, extract the plant details, and return unsaved attributes.

  Persisting is left to `GardenOptimizer.Plants.import_from_url/1` so this module stays a pure
  pipeline over two HTTP calls.
  """
  @spec extract(String.t()) :: {:ok, map()} | {:error, error()}
  def extract(url) do
    with :ok <- validate_url(url),
         {:ok, text} <- fetch_page(url),
         {:ok, attrs} <- ask_claude(url, text) do
      {:ok, Map.put(attrs, "source_url", url)}
    end
  end

  defp validate_url(url) when is_binary(url) do
    case URI.parse(String.trim(url)) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) -> :ok
      _ -> {:error, :invalid_url}
    end
  end

  defp validate_url(_), do: {:error, :invalid_url}

  defp fetch_page(url) do
    options =
      Application.get_env(:garden_optimizer, :page_fetch, []) |> Keyword.get(:req_options, [])

    [url: String.trim(url), receive_timeout: 20_000, max_redirects: 5]
    |> Keyword.merge(options)
    |> Req.new()
    |> Req.get()
    |> case do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        {:ok, to_text(body)}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("plant page #{url} returned #{status}")
        {:error, :page_unavailable}

      {:error, reason} ->
        Logger.warning("plant page #{url} could not be fetched: #{inspect(reason)}")
        {:error, :page_unavailable}
    end
  end

  @doc """
  Reduce an HTML document to the readable text Claude needs.

  Chrome and boilerplate are dropped first so the token budget goes to culture notes rather than
  navigation menus.
  """
  @spec to_text(String.t()) :: String.t()
  def to_text(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        document
        |> Floki.filter_out(Enum.join(@strip_selectors, ", "))
        |> Floki.text(sep: " ")
        |> normalize_whitespace()

      {:error, _reason} ->
        normalize_whitespace(html)
    end
  end

  defp normalize_whitespace(text) do
    text
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.slice(0, @max_page_chars)
  end

  defp ask_claude(url, text) do
    config = Application.get_env(:garden_optimizer, :anthropic, [])

    case Keyword.get(config, :api_key) do
      key when is_binary(key) and key != "" -> post_message(config, key, url, text)
      _ -> {:error, :missing_api_key}
    end
  end

  defp post_message(config, api_key, url, text) do
    body = %{
      model: Keyword.fetch!(config, :model),
      max_tokens: 2048,
      messages: [%{role: "user", content: prompt(url, text)}],
      # Constrained decoding: the response is guaranteed to satisfy this schema, so there is no
      # prose to strip and no fenced-JSON parsing to get wrong.
      output_config: %{format: %{type: "json_schema", schema: @schema}}
    }

    [
      url: "#{Keyword.fetch!(config, :base_url)}/v1/messages",
      json: body,
      headers: [
        {"x-api-key", api_key},
        {"anthropic-version", @anthropic_version}
      ],
      receive_timeout: 60_000
    ]
    |> Keyword.merge(Keyword.get(config, :req_options, []))
    |> Req.new()
    |> Req.post()
    |> case do
      {:ok, %Req.Response{status: 200, body: response}} ->
        decode_message(response)

      {:ok, %Req.Response{status: status, body: response}} ->
        Logger.warning("Anthropic API returned #{status}: #{inspect(response)}")
        {:error, :extraction_failed}

      {:error, reason} ->
        Logger.warning("Anthropic API request failed: #{inspect(reason)}")
        {:error, :extraction_failed}
    end
  end

  defp decode_message(%{"content" => content}) when is_list(content) do
    with %{"text" => text} <- Enum.find(content, &match?(%{"type" => "text"}, &1)),
         {:ok, attrs} when is_map(attrs) <- Jason.decode(text) do
      {:ok, attrs}
    else
      _ -> {:error, :extraction_failed}
    end
  end

  defp decode_message(_), do: {:error, :extraction_failed}

  @doc "The extraction prompt sent to Claude, exposed so tests can assert on it."
  def prompt(url, text) do
    """
    Here is the content of a plant page from #{url}:

    <page>
    #{text}
    </page>

    Extract the following details about the plant: variety name, common type of plant (e.g.
    tomato, broccoli, lettuce), the spacing requirements, when the plant should be direct sown
    or transplanted relative to the last frost date or first frost date, how long after planting
    the harvest will become available and whether the harvest is a one-time harvest or continuous.
    Structure the response as a JSON object with the following fields:
    - variety_name
    - common_type
    - sq_in: the number of square inches derived from the spacing requirements of the plant
    - planting_anchor: whether the planting date is relative to the first frost date or the last
    - anchor_offset_weeks_min: the minimum number of weeks relative to the anchor date that the
      plant should be planted (negative for before, positive for after)
    - anchor_offset_weeks_max: the maximum number of weeks relative to the anchor date that the
      plant should be planted (negative for before, positive for after)
    - days_to_maturity: the number of days from planting until harvest begins
    - harvest_type: "once" for a single harvest, "continuous" for repeated harvest over time
    """
  end

  @doc "Human-readable explanation for an import failure."
  @spec describe_error(error()) :: String.t()
  def describe_error(:missing_api_key),
    do: "Plant import needs an ANTHROPIC_API_KEY. Set one and restart the server."

  def describe_error(:invalid_url), do: "That doesn't look like a web address."

  def describe_error(:page_unavailable),
    do: "Couldn't load that page. Check the link and try again."

  def describe_error(:extraction_failed),
    do: "Couldn't read plant details from that page. Try a page with growing instructions."

  def describe_error({:invalid_plant, %Ecto.Changeset{} = changeset}) do
    details =
      changeset
      |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
      |> Enum.map_join(", ", fn {field, msgs} -> "#{field} #{Enum.join(msgs, " and ")}" end)

    "The details read from that page don't make sense: #{details}."
  end

  @doc false
  def schema, do: @schema

  @doc false
  def plant_module, do: Plant
end
