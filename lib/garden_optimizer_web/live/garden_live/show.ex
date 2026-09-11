defmodule GardenOptimizerWeb.GardenLive.Show do
  @moduledoc """
  The workbench: beds, plants, quantities, and the capacity meter that governs them.

  Importing a plant costs a page fetch plus a model call, so it runs as an async task and the
  form stays interactive. Quantities are stored as one row per plant unit, but the UI only ever
  speaks in counts — `Gardens.set_plant_quantity/3` reconciles the difference.
  """
  use GardenOptimizerWeb, :live_view

  alias GardenOptimizer.Gardens
  alias GardenOptimizer.Gardens.GrowingArea
  alias GardenOptimizer.Plants
  alias GardenOptimizer.Plants.Importer
  alias GardenOptimizer.Scheduling

  @common_beds [
    {"4' × 8'", 48, 96},
    {"4' × 4'", 48, 48},
    {"2.5' × 9'", 30, 108},
    {"3' × 6'", 36, 72}
  ]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    garden = Gardens.get_garden!(socket.assigns.current_scope, id)

    {:ok,
     socket
     |> assign(:garden, garden)
     |> assign(:page_title, garden.name)
     |> assign(:common_beds, @common_beds)
     |> assign(:importing, false)
     |> assign(:import_url, "")
     |> assign(:building, false)
     |> assign(:area_form, to_form(Gardens.change_growing_area(%GrowingArea{})))
     |> assign(:area_preview, nil)
     |> reload()}
  end

  ## Growing areas

  @impl true
  def handle_event("validate_area", %{"growing_area" => params}, socket) do
    changeset =
      %GrowingArea{}
      |> Gardens.change_growing_area(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:area_form, to_form(changeset))
     |> assign(:area_preview, area_preview(params))}
  end

  def handle_event("add_area", %{"growing_area" => params}, socket) do
    params = Map.put_new(params, "name", "Bed #{length(socket.assigns.growing_areas) + 1}")

    case Gardens.add_growing_area(socket.assigns.garden, params) do
      {:ok, _area} ->
        {:noreply,
         socket
         |> assign(:area_form, to_form(Gardens.change_growing_area(%GrowingArea{})))
         |> assign(:area_preview, nil)
         |> reload()}

      {:error, changeset} ->
        {:noreply, assign(socket, :area_form, to_form(changeset))}
    end
  end

  def handle_event("preset_area", %{"width" => width_in, "length" => length_in}, socket) do
    name = "Bed #{length(socket.assigns.growing_areas) + 1}"

    case Gardens.add_growing_area(socket.assigns.garden, %{
           "name" => name,
           "width_in" => width_in,
           "length_in" => length_in
         }) do
      {:ok, _area} -> {:noreply, reload(socket)}
      {:error, _changeset} -> {:noreply, put_flash(socket, :error, "Couldn't add that bed.")}
    end
  end

  def handle_event("delete_area", %{"id" => id}, socket) do
    socket.assigns.current_scope
    |> Gardens.get_growing_area!(id)
    |> Gardens.delete_growing_area()

    {:noreply, reload(socket)}
  end

  ## Plants

  def handle_event("import", %{"url" => url}, socket) do
    url = String.trim(url)

    if url == "" do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(importing: true, import_url: url)
       |> start_async(:import, fn -> Plants.import_from_url(url) end)}
    end
  end

  def handle_event("set_quantity", %{"plant-id" => plant_id, "quantity" => quantity}, socket) do
    case Integer.parse(to_string(quantity)) do
      {n, _} when n >= 0 -> {:noreply, apply_quantity(socket, plant_id, n)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("step_quantity", %{"plant-id" => plant_id, "by" => by}, socket) do
    current = Map.get(socket.assigns.quantities_by_plant, plant_id, 0)
    {by, _} = Integer.parse(by)
    {:noreply, apply_quantity(socket, plant_id, max(current + by, 0))}
  end

  def handle_event("remove_plant", %{"plant-id" => plant_id}, socket) do
    {:noreply, apply_quantity(socket, plant_id, 0)}
  end

  ## Building

  def handle_event("build", _params, socket) do
    garden = socket.assigns.garden

    {:noreply,
     socket
     |> assign(:building, true)
     |> start_async(:build, fn -> Scheduling.build(garden) end)}
  end

  @impl true
  def handle_async(:import, {:ok, {:ok, plant}}, socket) do
    # Set quantity to 1 by default when a plant is imported
    _ = Gardens.set_plant_quantity(socket.assigns.garden, plant, 1)

    {:noreply,
     socket
     |> assign(importing: false, import_url: "")
     |> reload()}
  end

  def handle_async(:import, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:importing, false)
     |> put_flash(:error, Importer.describe_error(reason))}
  end

  def handle_async(:import, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:importing, false)
     |> put_flash(:error, "That import didn't finish. Try again.")}
  end

  def handle_async(:build, {:ok, {:ok, _schedule}}, socket) do
    {:noreply,
     socket
     |> assign(:building, false)
     |> push_navigate(to: ~p"/gardens/#{socket.assigns.garden}/schedule")}
  end

  def handle_async(:build, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:building, false)
     |> put_flash(:error, build_error(reason))}
  end

  def handle_async(:build, {:exit, _reason}, socket) do
    {:noreply,
     socket |> assign(:building, false) |> put_flash(:error, "Building the garden failed.")}
  end

  defp build_error(:no_growing_areas), do: "Add at least one growing area first."
  defp build_error(:no_plants), do: "Choose some plants first."
  defp build_error(_), do: "Building the garden failed."

  ## Helpers

  defp apply_quantity(socket, plant_id, quantity) do
    plant = Plants.get_plant!(plant_id)

    case Gardens.set_plant_quantity(socket.assigns.garden, plant, quantity) do
      {:ok, _quantity} ->
        reload(socket)

      {:error, :over_capacity} ->
        put_flash(socket, :error, "That would take the garden past 100% full.")

      {:error, :no_growing_areas} ->
        put_flash(socket, :error, "Add a growing area before choosing plants.")
    end
  end

  defp reload(socket) do
    garden = socket.assigns.garden
    quantities = Gardens.plant_quantities(garden)
    chosen = Enum.filter(quantities, fn {_plant, quantity} -> quantity > 0 end)

    socket
    |> assign(:growing_areas, Gardens.list_growing_areas(garden))
    |> assign(:quantities, quantities)
    |> assign(:chosen, chosen)
    |> assign(:quantities_by_plant, Map.new(quantities, fn {p, n} -> {p.id, n} end))
    |> assign(:capacity, Gardens.capacity(garden))
    |> assign(:schedule, Scheduling.get_schedule(garden))
  end

  defp anchor_label(%{planting_anchor: :last_frost}), do: "last frost"
  defp anchor_label(%{planting_anchor: :first_frost}), do: "first frost"

  # Reads the planting window as a gardener would say it: "6–4w before last frost", not
  # "-6 to -4". A window straddling the frost date needs both sides spelled out.
  defp offset_label(plant) do
    anchor = anchor_label(plant)
    min = plant.anchor_offset_weeks_min
    max = plant.anchor_offset_weeks_max

    case {min, max} do
      {n, n} when n == 0 -> "at #{anchor}"
      {n, n} when n < 0 -> "#{abs(n)}w before #{anchor}"
      {n, n} -> "#{n}w after #{anchor}"
      {min, max} when max <= 0 and min < 0 and max == 0 -> "up to #{abs(min)}w before #{anchor}"
      {min, max} when max < 0 -> "#{abs(min)}–#{abs(max)}w before #{anchor}"
      {min, max} when min > 0 -> "#{min}–#{max}w after #{anchor}"
      {0, max} -> "up to #{max}w after #{anchor}"
      {min, max} -> "#{abs(min)}w before to #{max}w after #{anchor}"
    end
  end

  defp spacing_label(plant) do
    case GardenOptimizer.Scheduling.Footprint.for_sq_in(plant.sq_in) do
      {:shared, sq_in} ->
        per_square = div(GardenOptimizer.Scheduling.Footprint.square_capacity(), sq_in)
        if per_square > 1, do: "#{per_square} per square", else: "1 square"

      {:block, w, h} ->
        "#{w}×#{h} squares"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@garden.name}
        <:subtitle>
          Zip {@garden.zip_code} · {format_date(@garden.last_frost_date)} → {format_date(
            @garden.first_frost_date
          )}
        </:subtitle>
        <:actions>
          <.link :if={@schedule} navigate={~p"/gardens/#{@garden}/schedule"} class="btn btn-ghost">
            View schedule
          </.link>
          <button
            type="button"
            phx-click="build"
            disabled={@building or @chosen == [] or @growing_areas == []}
            class="btn btn-primary"
          >
            <span :if={@building} class="loading loading-spinner loading-xs"></span>
            {if @schedule, do: "Re-build garden", else: "Build garden"}
          </button>
        </:actions>
      </.header>

      <div class="mt-8 grid gap-6 lg:grid-cols-[1fr_20rem] lg:items-start">
        <div class="space-y-6">
          <.growing_areas_section
            growing_areas={@growing_areas}
            area_form={@area_form}
            area_preview={@area_preview}
            common_beds={@common_beds}
          />
          <.plants_section
            quantities={@quantities}
            importing={@importing}
            capacity={@capacity}
            growing_areas={@growing_areas}
          />
        </div>

        <.capacity_panel
          :if={is_nil(@schedule)}
          capacity={@capacity}
          growing_areas={@growing_areas}
          schedule={@schedule}
        />
      </div>
    </Layouts.app>
    """
  end

  ## Sections

  attr :growing_areas, :list, required: true
  attr :area_form, :any, required: true
  attr :area_preview, :string, default: nil
  attr :common_beds, :list, required: true

  defp growing_areas_section(assigns) do
    ~H"""
    <section class="rounded-2xl border border-base-300 bg-base-100">
      <div class="flex items-baseline justify-between border-b border-base-300 px-5 py-4">
        <h2 class="text-base font-semibold tracking-tight">Growing areas</h2>
        <p class="text-sm text-base-content/50">
          {total_squares(@growing_areas)} planting squares
        </p>
      </div>

      <div :if={@growing_areas == []} class="px-5 py-8 text-center text-sm text-base-content/60">
        Add a raised bed to get started. Every bed is divided into 6″ × 6″ squares.
      </div>

      <ul :if={@growing_areas != []} class="divide-y divide-base-300">
        <li
          :for={area <- @growing_areas}
          class="flex items-center justify-between gap-4 px-5 py-3.5"
        >
          <div class="min-w-0">
            <p class="truncate font-medium">{area.name}</p>
            <p class="text-sm text-base-content/55">
              {dimension_label(area)} · {GrowingArea.rows(area)} × {GrowingArea.cols(area)} squares
            </p>
          </div>
          <button
            type="button"
            phx-click="delete_area"
            phx-value-id={area.id}
            data-confirm={"Remove #{area.name}?"}
            class="btn btn-ghost btn-sm text-base-content/50 hover:text-error"
            aria-label={"Remove #{area.name}"}
          >
            <.icon name="hero-trash" class="size-4" />
          </button>
        </li>
      </ul>

      <div class="border-t border-base-300 px-5 py-4">
        <div class="flex flex-wrap gap-2">
          <button
            :for={{label, width, length} <- @common_beds}
            type="button"
            phx-click="preset_area"
            phx-value-width={width}
            phx-value-length={length}
            class="btn btn-sm btn-outline"
          >
            <.icon name="hero-plus" class="size-3.5" /> {label}
          </button>
        </div>

        <.form
          for={@area_form}
          id="area-form"
          phx-change="validate_area"
          phx-submit="add_area"
          class="mt-4"
        >
          <div class="flex flex-wrap items-start gap-3">
            <div class="w-40 pt-0">
              <.input
                field={@area_form[:name]}
                label="Name"
                placeholder="Bed 1"
                autocomplete="off"
                show_errors={false}
              />
            </div>
            <div class="w-28 pt-0">
              <.input
                field={@area_form[:width_in]}
                type="number"
                label="Width (in)"
                min="6"
                step="6"
                show_errors={false}
              />
            </div>
            <div class="w-28 pt-0">
              <.input
                field={@area_form[:length_in]}
                type="number"
                label="Length (in)"
                min="6"
                step="6"
                show_errors={false}
              />
            </div>
            <div class="flex self-center items-end pt-0">
              <.button class="btn btn-outline h-12">Add bed</.button>
            </div>
          </div>

          <div class="min-h-6 mt-1">
            <p
              :if={
                Phoenix.Component.used_input?(@area_form[:name]) and @area_form[:name].errors != []
              }
              class="flex gap-2 items-start text-sm text-error"
            >
              <.icon name="hero-exclamation-circle" class="size-5 shrink-0 mt-0.5" />
              <span>
                <strong>Name:</strong> {Enum.map_join(
                  @area_form[:name].errors,
                  ", ",
                  &translate_error/1
                )}
              </span>
            </p>
            <p
              :if={
                Phoenix.Component.used_input?(@area_form[:width_in]) and
                  @area_form[:width_in].errors != []
              }
              class="flex gap-2 items-start text-sm text-error"
            >
              <.icon name="hero-exclamation-circle" class="size-5 shrink-0 mt-0.5" />
              <span>
                <strong>Width (in):</strong> {Enum.map_join(
                  @area_form[:width_in].errors,
                  ", ",
                  &translate_error/1
                )}
              </span>
            </p>
            <p
              :if={
                Phoenix.Component.used_input?(@area_form[:length_in]) and
                  @area_form[:length_in].errors != []
              }
              class="flex gap-2 items-start text-sm text-error"
            >
              <.icon name="hero-exclamation-circle" class="size-5 shrink-0 mt-0.5" />
              <span>
                <strong>Length (in):</strong> {Enum.map_join(
                  @area_form[:length_in].errors,
                  ", ",
                  &translate_error/1
                )}
              </span>
            </p>
          </div>

          <p class="mt-3 text-xs text-base-content/50">
            <span :if={@area_preview}>{@area_preview}</span>
            <span :if={is_nil(@area_preview)}>
              Beds are planned in 6″ squares, so both dimensions step by 6.
            </span>
          </p>
        </.form>
      </div>
    </section>
    """
  end

  attr :quantities, :list, required: true
  attr :importing, :boolean, required: true
  attr :capacity, :map, required: true
  attr :growing_areas, :list, required: true

  defp plants_section(assigns) do
    ~H"""
    <section class="rounded-2xl border border-base-300 bg-base-100">
      <div class="border-b border-base-300 px-5 py-4">
        <h2 class="text-base font-semibold tracking-tight">Plants</h2>
        <p class="mt-0.5 text-sm text-base-content/55">
          Paste a link to a seed or plant page and we'll read the growing details from it.
        </p>
      </div>

      <div class="px-5 py-4">
        <form phx-submit="import" class="flex gap-2">
          <input
            type="url"
            name="url"
            placeholder="https://www.example-seeds.com/cherokee-purple-tomato"
            disabled={@importing}
            autocomplete="off"
            class="input input-bordered w-full"
          />
          <button type="submit" disabled={@importing} class="btn btn-primary whitespace-nowrap">
            <span :if={@importing} class="loading loading-spinner loading-xs"></span>
            {if @importing, do: "Reading…", else: "Add plant"}
          </button>
        </form>
        <p :if={@importing} class="mt-2 text-xs text-base-content/50">
          Fetching the page and reading its growing instructions — this takes a few seconds.
        </p>
      </div>

      <div
        :if={@quantities == []}
        class="border-t border-base-300 px-5 py-8 text-center text-sm text-base-content/60"
      >
        No plants yet. Paste a link above to add one.
      </div>

      <ul :if={@quantities != []} class="divide-y divide-base-300 border-t border-base-300">
        <li
          :for={{plant, quantity} <- @quantities}
          class={["flex items-center gap-4 px-5 py-4", quantity == 0 && "opacity-60"]}
        >
          <span class={[
            "size-2.5 shrink-0 rounded-full",
            if(quantity > 0, do: plant_color(plant.id).bg, else: "bg-base-300")
          ]}>
          </span>

          <div class="min-w-0 flex-1">
            <p class="truncate font-medium">{plant.variety_name}</p>
            <p class="truncate text-sm text-base-content/55">
              {plant.common_type} · {spacing_label(plant)} · plant {offset_label(plant)}
            </p>
            <p class="truncate text-xs text-base-content/45">
              {plant.days_to_maturity} days to harvest · {if plant.harvest_type == :once,
                do: "one-time harvest",
                else: "harvest continuously"}
            </p>
          </div>

          <div class="flex shrink-0 items-center gap-1">
            <button
              type="button"
              phx-click="step_quantity"
              phx-value-plant-id={plant.id}
              phx-value-by="-1"
              class="btn btn-sm btn-ghost"
              aria-label={"One fewer #{plant.variety_name}"}
            >
              <.icon name="hero-minus" class="size-4" />
            </button>
            <form phx-change="set_quantity">
              <input type="hidden" name="plant-id" value={plant.id} />
              <input
                type="number"
                name="quantity"
                value={quantity}
                min="0"
                class="input input-bordered input-sm w-16 text-center"
                aria-label={"How many #{plant.variety_name}"}
              />
            </form>
            <button
              type="button"
              phx-click="step_quantity"
              phx-value-plant-id={plant.id}
              phx-value-by="1"
              disabled={@capacity.percent_used >= 100}
              class="btn btn-sm btn-ghost"
              aria-label={"One more #{plant.variety_name}"}
            >
              <.icon name="hero-plus" class="size-4" />
            </button>
            <button
              type="button"
              phx-click="remove_plant"
              phx-value-plant-id={plant.id}
              class="btn btn-ghost btn-sm ml-1 text-base-content/40 hover:text-error"
              aria-label={"Remove #{plant.variety_name}"}
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>
        </li>
      </ul>
    </section>
    """
  end

  attr :capacity, :map, required: true
  attr :growing_areas, :list, required: true
  attr :schedule, :any, required: true

  defp capacity_panel(assigns) do
    ~H"""
    <aside class="rounded-2xl border border-base-300 bg-base-100 p-5 lg:sticky lg:top-20">
      <h2 class="text-base font-semibold tracking-tight">Space used</h2>

      <div class="mt-4 flex items-baseline gap-2">
        <span class={[
          "text-4xl font-semibold tabular-nums tracking-tight",
          @capacity.percent_used >= 100 && "text-error",
          @capacity.percent_used >= 85 && @capacity.percent_used < 100 && "text-warning"
        ]}>
          {@capacity.percent_used}
        </span>
        <span class="text-lg text-base-content/50">%</span>
      </div>

      <div class="mt-3 h-2.5 overflow-hidden rounded-full bg-base-300">
        <div
          class={[
            "h-full rounded-full transition-all duration-500",
            cond do
              @capacity.percent_used >= 100 -> "bg-error"
              @capacity.percent_used >= 85 -> "bg-warning"
              true -> "bg-emerald-500"
            end
          ]}
          style={"width: #{min(@capacity.percent_used, 100)}%"}
        >
        </div>
      </div>

      <dl class="mt-5 space-y-2.5 text-sm">
        <div class="flex justify-between">
          <dt class="text-base-content/60">Beds</dt>
          <dd class="font-medium tabular-nums">{length(@growing_areas)}</dd>
        </div>
        <div class="flex justify-between">
          <dt class="text-base-content/60">Planting squares</dt>
          <dd class="font-medium tabular-nums">{@capacity.total_squares}</dd>
        </div>
        <div class="flex justify-between">
          <dt class="text-base-content/60">Square inches used</dt>
          <dd class="font-medium tabular-nums">
            {@capacity.used_sq_in} / {@capacity.total_sq_in}
          </dd>
        </div>
      </dl>

      <p class="mt-5 border-t border-base-300 pt-4 text-xs leading-relaxed text-base-content/50">
        Space is measured against whole 6″ squares. Small plants share a square — four radishes fit
        in one — while anything larger claims whole squares. This is a snapshot: the schedule reuses
        squares across the season, so a garden at 60% can still grow far more than 60% of a season's
        worth of food.
      </p>

      <p
        :if={@schedule}
        class="mt-4 rounded-lg bg-base-200/60 px-3 py-2.5 text-xs text-base-content/60"
      >
        Schedule last built {format_date(DateTime.to_date(@schedule.generated_at))}. Re-build after
        changing plants or beds.
      </p>
    </aside>
    """
  end

  # Shows the grid a bed will actually become, so the 6" rule reads as a consequence rather than
  # an arbitrary rule. Falls back to naming the two nearest valid sizes when a dimension is off.
  defp area_preview(%{"width_in" => width, "length_in" => length}) do
    with {:ok, width} <- parse_dimension(width),
         {:ok, length} <- parse_dimension(length) do
      case {rem(width, 6), rem(length, 6)} do
        {0, 0} ->
          "#{div(length, 6)} × #{div(width, 6)} squares — #{div(length * width, 36)} in total."

        _ ->
          off = if rem(width, 6) != 0, do: width, else: length
          {lower, upper} = GrowingArea.nearest_sizes(off)
          ~s(#{off}" isn't a whole number of 6" squares — try #{lower}" or #{upper}".)
      end
    else
      _ -> nil
    end
  end

  defp area_preview(_params), do: nil

  defp parse_dimension(value) do
    case Integer.parse(to_string(value)) do
      {n, ""} when n >= 6 -> {:ok, n}
      _ -> :error
    end
  end

  defp total_squares(areas), do: areas |> Enum.map(&GrowingArea.squares/1) |> Enum.sum()

  defp dimension_label(area) do
    "#{inches_label(area.width_in)} × #{inches_label(area.length_in)}"
  end

  defp inches_label(inches) do
    feet = inches / 12

    if feet == Float.round(feet, 0) do
      "#{trunc(feet)}′"
    else
      "#{Float.round(feet, 1)}′"
    end
  end
end
