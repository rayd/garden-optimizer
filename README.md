# Garden Optimizer

Square-foot garden planning: lay out raised beds, choose plants, and get a week-by-week planting
schedule that reuses each 6″ × 6″ square across the season.

The point of the tool is succession planning. A square that holds radishes in April is empty by
late May, and the **free planting blocks** report is how you find those windows — every square
that sits completely empty for five or more consecutive weeks, with the date it opens and how
long it lasts.

## Setup

Requires Elixir 1.20 / OTP 29 (see `.tool-versions`) and Postgres on `localhost:5432`.

```bash
mix setup                      # deps, database, migrations, assets
export ANTHROPIC_API_KEY=...   # needed only for importing plants from a URL
mix phx.server                 # http://localhost:4000
```

`mix run priv/repo/seeds.exs` builds a realistic garden — nine beds, six varieties, a full
schedule — without needing an API key. Frost dates still come from the live API.

## How it works

**Frost dates** (`GardenOptimizer.Frost`) come from a zip code lookup. The upstream API reports
`MM/DD` with no year at several probability levels; we take the 50% column and resolve it to the
*next* spring frost, then the fall frost that closes that same season.

**Plant import** (`GardenOptimizer.Plants.Importer`) fetches the page with `Req`, strips it to
readable text with `Floki`, and sends that text to `claude-haiku-4-5` under a JSON schema
(`output_config.format`), so the response is always shaped correctly. Fetching the page ourselves
rather than asking the model to do it keeps the request testable against a fixture and makes
"couldn't reach the page" distinguishable from "couldn't understand it".

**Scheduling** (`GardenOptimizer.Scheduling`) is a pure core with a thin persistence wrapper:

- `WeekGrid` — weeks are 7-day blocks aligned to the last frost date, so a plant's eligible
  window is exactly its `anchor_offset_weeks_min..max`. Display week 1 is the earliest week
  anything in the garden could be planted, which may be well before the last frost.
- `Footprint` — every square holds 36 sq in. A plant at or under that *shares* a square
  (four radishes at 9 sq in each); anything larger claims a rectangle of whole squares.
- `Strategy.EarliestFit` — greedy first fit, behind a behaviour so a packing optimizer can
  replace it without touching the schema, the persistence layer, or the UI.
- `FreeBlocks` — maximal runs of completely-empty weeks per square, five weeks or longer.
- `Output` — materializes the `weeks -> growing_areas -> squares` structure on demand. Each cell
  is a **list** of `garden_plants.id`, so a shared square names every plant in it, and `[]` means
  free. A season is ~30k cells, so it is derived from a few hundred assignment rows rather than
  stored.

Quantity is stored as one `garden_plants` row per plant *unit*, which is what lets a grid cell
name the exact unit it holds. The UI only ever speaks in counts;
`Gardens.set_plant_quantity/3` reconciles the difference.

## Tests

```bash
mix test        # no test touches the network — both HTTP clients use Req.Test stubs
mix precommit   # warnings-as-errors, unused deps, format, test
```

## Known limitations

- The space meter measures **area**; the layout packs **rectangles**. A garden can read under
  100% and still not fit — 14 tomatoes' worth of area exists in a 4′ × 8′ bed, but only ten 3×3
  blocks fit in a 16 × 8 grid. Anything that can't be placed is reported on the schedule rather
  than dropped.
- Display week numbers shift when the plant list changes, since week 1 is defined by the earliest
  plantable week. The UI therefore leads with calendar dates.
- Plant import cannot read pages that render their content with JavaScript.
