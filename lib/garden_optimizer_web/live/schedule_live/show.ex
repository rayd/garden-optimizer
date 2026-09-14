defmodule GardenOptimizerWeb.ScheduleLive.Show do
  @moduledoc """
  The planting schedule, one week at a time.

  Only the selected week's grid is materialized — the full season is ~30k cells and there is no
  reason to build the other 30 weeks to render one. Dates lead the interface because week numbers
  shift whenever the plant list changes.
  """
  use GardenOptimizerWeb, :live_view

  alias GardenOptimizer.Gardens
  alias GardenOptimizer.Plants
  alias GardenOptimizer.Plants.Importer
  alias GardenOptimizer.Scheduling

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    garden = Gardens.get_garden!(socket.assigns.current_scope, id)

    case Scheduling.get_schedule(garden) do
      nil ->
        {:ok,
         socket
         |> put_flash(:info, "Build the garden to see its planting schedule.")
         |> push_navigate(to: ~p"/gardens/#{garden}")}

      schedule ->
        {:ok,
         socket
         |> assign(:garden, garden)
         |> assign(:page_title, "#{garden.name} schedule")
         |> assign(:schedule, schedule)
         |> assign(:plants_by_unit, plants_by_unit(schedule))
         |> assign(:unplaced, Scheduling.unplaced_details(schedule))
         |> assign(:legend, legend(schedule))
         |> assign(:filling, nil)
         |> assign(:unsaved, false)
         |> assign(:importing, false)
         |> assign(:free_squares, Scheduling.free_squares_by_bed(schedule))
         |> select_week(first_interesting_week(schedule))}
    end
  end

  @impl true
  def handle_event("select_week", %{"week" => week}, socket) do
    {week, _} = Integer.parse(week)
    {:noreply, select_week(socket, clamp(week, socket.assigns.schedule.week_count))}
  end

  def handle_event("step_week", %{"by" => by}, socket) do
    {by, _} = Integer.parse(by)
    week = socket.assigns.week + by
    {:noreply, select_week(socket, clamp(week, socket.assigns.schedule.week_count))}
  end

  def handle_event("fill_block", %{"bed" => bed_id, "from" => from, "to" => to}, socket) do
    window = {Date.from_iso8601!(from), Date.from_iso8601!(to)}
    {:noreply, open_sidebar(socket, bed_id, window)}
  end

  # Every way out of the sidebar saves. The fills are already written as plant rows, so closing
  # without a build would leave the schedule behind describing a garden that no longer exists.
  def handle_event("close_fill", _params, socket) do
    {:noreply, socket |> save_fills() |> assign(filling: nil, importing: false)}
  end

  def handle_event(
        "set_block_quantity",
        %{"plant-id" => plant_id, "quantity" => quantity},
        socket
      ) do
    case Integer.parse(to_string(quantity)) do
      {n, _} when n >= 0 -> {:noreply, apply_block_quantity(socket, plant_id, n)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("step_block_quantity", %{"plant-id" => plant_id, "by" => by}, socket) do
    {by, _} = Integer.parse(by)
    current = Map.get(socket.assigns.filling.quantities, plant_id, 0)
    {:noreply, apply_block_quantity(socket, plant_id, max(current + by, 0))}
  end

  def handle_event("import", %{"url" => url}, socket) do
    url = String.trim(url)

    if url == "" do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(:importing, true)
       |> start_async(:import, fn -> Plants.import_from_url(url) end)}
    end
  end

  @impl true
  def handle_async(:import, {:ok, {:ok, plant}}, socket) do
    {:noreply,
     socket
     |> assign(:importing, false)
     |> put_flash(:info, "Added #{plant.variety_name}.")
     |> refresh_sidebar()}
  end

  def handle_async(:import, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket |> assign(:importing, false) |> put_flash(:error, Importer.describe_error(reason))}
  end

  def handle_async(:import, {:exit, _reason}, socket) do
    {:noreply,
     socket |> assign(:importing, false) |> put_flash(:error, "That import didn't finish.")}
  end

  defp apply_block_quantity(socket, plant_id, quantity) do
    %{filling: filling, garden: garden} = socket.assigns
    plant = Plants.get_plant!(plant_id)

    case Scheduling.fill_block(garden, plant, filling.group, quantity) do
      :ok ->
        socket
        |> assign(:unsaved, true)
        |> refresh_sidebar()

      {:error, :no_room} ->
        put_flash(socket, :error, no_room_message(filling, plant, quantity))
    end
  end

  defp no_room_message(%{group: group} = filling, plant, quantity) do
    capacity = Map.get(filling.capacities, plant.id, 0)

    cond do
      Scheduling.block_capacity(group, plant, []) == 0 ->
        "#{plant.variety_name} needs more room than these #{pluralize(group.count, "square")} offer."

      capacity == 0 ->
        "There's no room left in these squares for #{plant.variety_name}."

      quantity > capacity ->
        "These squares hold at most #{pluralize(capacity, plant.variety_name)}."

      # Within the area cap, but the rectangles don't pack.
      true ->
        "These squares can't fit #{pluralize(quantity, plant.variety_name)}."
    end
  end

  # Fills only touch plant rows; this is the one build that turns them into a schedule.
  defp save_fills(%{assigns: %{unsaved: false}} = socket), do: socket

  defp save_fills(socket) do
    case Scheduling.build(socket.assigns.garden) do
      {:ok, schedule} ->
        socket |> assign(:unsaved, false) |> reload_schedule(schedule)

      {:error, _reason} ->
        put_flash(socket, :error, "Couldn't update the schedule with those plantings.")
    end
  end

  # Re-derives everything downstream of the schedule, keeping the week the gardener was looking at.
  defp reload_schedule(socket, schedule) do
    socket
    |> assign(:schedule, schedule)
    |> assign(:plants_by_unit, plants_by_unit(schedule))
    |> assign(:unplaced, Scheduling.unplaced_details(schedule))
    |> assign(:legend, legend(schedule))
    |> assign(:free_squares, Scheduling.free_squares_by_bed(schedule))
    |> select_week(clamp(socket.assigns.week, schedule.week_count))
  end

  defp open_sidebar(socket, bed_id, window) do
    case find_group(socket.assigns.free_squares, bed_id, window) do
      nil -> assign(socket, :filling, nil)
      {bed, group} -> assign(socket, :filling, build_filling(socket, bed, group))
    end
  end

  # The sidebar stays scoped to the squares that were clicked, even as filling them shrinks that row
  # or removes it from the list behind. Re-resolving the group would drop the units already planted
  # out of scope, so they could no longer be stepped back down or counted against the cap.
  defp refresh_sidebar(%{assigns: %{filling: nil}} = socket), do: socket

  defp refresh_sidebar(socket) do
    %{filling: filling} = socket.assigns
    assign(socket, :filling, build_filling(socket, filling.growing_area, filling.group))
  end

  # Identified by its whole window, and by dates rather than week numbers. Both halves matter:
  # week 1 is defined by the earliest plantable week in the garden, so adding a crop that goes in
  # earlier renumbers every week; and two sets of squares in one bed can open on the same day yet
  # close on different ones, which makes them different opportunities with different crops on offer.
  defp find_group(free_squares, bed_id, {from, to}) do
    Enum.find_value(free_squares, fn %{growing_area: bed, groups: groups} ->
      if bed.id == bed_id do
        case Enum.find(groups, &(&1.start_date == from and &1.window_end_date == to)) do
          nil -> nil
          group -> {bed, group}
        end
      end
    end)
  end

  defp build_filling(socket, bed, group) do
    garden = socket.assigns.garden
    garden_plants = Gardens.list_garden_plants(garden)
    catalog = Plants.list_plants()
    offered = Scheduling.plantable_in_group(garden, garden_plants, group, catalog)

    garden_totals =
      garden_plants |> Enum.frequencies_by(& &1.plant_id)

    quantities =
      Map.new(offered, fn plant ->
        {plant.id, Scheduling.block_unit_count(garden_plants, plant, group)}
      end)

    %{
      growing_area: bed,
      group: group,
      offered: offered,
      quantities: quantities,
      garden_totals: garden_totals,
      # From plant rows, not the schedule: the schedule isn't rebuilt until the sidebar closes.
      remaining: Scheduling.block_squares_free(garden_plants, group),
      capacities: Map.new(offered, &{&1.id, Scheduling.block_capacity(group, &1, garden_plants)})
    }
  end

  defp clamp(week, week_count), do: week |> max(1) |> min(week_count)

  defp select_week(socket, week) do
    schedule = socket.assigns.schedule
    %{weeks: [rendered]} = Scheduling.to_output(schedule, weeks: [week])

    socket
    |> assign(:week, week)
    |> assign(:rendered_week, rendered)
    |> assign(:planted, Scheduling.planted_in_week(schedule, week))
    |> assign(:cleared, Scheduling.cleared_in_week(schedule, week))
    |> assign(:free_blocks, Scheduling.free_blocks_in_week(schedule, week))
  end

  # Open on the first week that actually has something going in the ground.
  defp first_interesting_week(schedule) do
    schedule.assignments |> Enum.map(& &1.plant_week) |> Enum.min(fn -> 1 end)
  end

  defp plants_by_unit(schedule) do
    Map.new(schedule.assignments, &{&1.garden_plant_id, &1.garden_plant.plant})
  end

  defp legend(schedule) do
    schedule.assignments
    |> Enum.map(& &1.garden_plant.plant)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(&{&1.common_type, &1.variety_name})
  end

  # Weeks with something happening get a tick in the scrubber, so the season reads at a glance.
  defp week_activity(schedule) do
    planted = schedule.assignments |> Enum.map(& &1.plant_week) |> Enum.frequencies()
    cleared = schedule.assignments |> Enum.map(&(&1.last_week + 1)) |> Enum.frequencies()
    opened = schedule.free_blocks |> Enum.map(& &1.start_week) |> Enum.frequencies()

    Map.new(1..schedule.week_count//1, fn week ->
      {week,
       %{
         planted: Map.get(planted, week, 0),
         cleared: Map.get(cleared, week, 0),
         opened: Map.get(opened, week, 0)
       }}
    end)
  end

  @impl true
  def render(assigns) do
    assigns = assign_new(assigns, :activity, fn -> week_activity(assigns.schedule) end)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@garden.name} schedule
        <:subtitle>
          {@schedule.week_count} weeks · {format_date(@schedule.week_1_start_date)} through {format_date(
            @garden.first_frost_date
          )}
        </:subtitle>
        <:actions>
          <.link navigate={~p"/gardens/#{@garden}"} class="btn btn-ghost">
            <.icon name="hero-arrow-left" class="size-4" /> Edit plants
          </.link>
        </:actions>
      </.header>

      <div
        :if={@unplaced != []}
        class="mt-6 rounded-xl border border-warning/40 bg-warning/10 px-4 py-3.5"
      >
        <p class="flex items-center gap-2 text-sm font-medium">
          <.icon name="hero-exclamation-triangle" class="size-4 text-warning" />
          Some plants couldn't be placed
        </p>
        <ul class="mt-2 space-y-1 pl-6 text-sm text-base-content/70">
          <li :for={item <- @unplaced} class="list-disc">
            {pluralize(item.count, item.variety_name)} — {item.reason}.
          </li>
        </ul>
        <p class="mt-2 pl-6 text-xs text-base-content/50">
          The space meter measures area; fitting real rectangles into real beds leaves gaps. Reduce a
          quantity or add a bed, then re-build.
        </p>
      </div>

      <.week_scrubber
        schedule={@schedule}
        week={@week}
        activity={@activity}
        week_1_start_date={@schedule.week_1_start_date}
      />

      <.free_squares_section free_squares={@free_squares} />

      <div class="mt-6 grid gap-6 lg:grid-cols-[1fr_20rem] lg:items-start">
        <div class="space-y-5">
          <.bed_grid
            :for={area <- @rendered_week.growing_areas}
            area={area}
            plants_by_unit={@plants_by_unit}
            planted={@planted}
          />
        </div>

        <div class="space-y-5">
          <.week_activity_panel
            planted={@planted}
            cleared={@cleared}
            free_blocks={@free_blocks}
            week={@week}
          />
          <.legend_panel legend={@legend} />
        </div>
      </div>

      <.fill_sidebar :if={@filling} filling={@filling} importing={@importing} unsaved={@unsaved} />
    </Layouts.app>
    """
  end

  ## Free planting squares

  attr :free_squares, :list, required: true

  defp free_squares_section(assigns) do
    ~H"""
    <section id="free-squares" class="mt-6 rounded-2xl border border-base-300 bg-base-100">
      <div class="flex items-baseline justify-between border-b border-base-300 px-5 py-4">
        <div>
          <h2 class="text-base font-semibold tracking-tight">Free planting squares</h2>
          <p class="mt-0.5 text-sm text-base-content/55">
            Squares sitting empty for five weeks or more — room for another crop.
          </p>
        </div>
        <p class="shrink-0 text-sm text-base-content/50">
          {total_free(@free_squares)} across {pluralize(length(@free_squares), "bed")}
        </p>
      </div>

      <p :if={@free_squares == []} class="px-5 py-8 text-center text-sm text-base-content/55">
        The garden is fully committed all season — nothing sits empty long enough to plant into.
      </p>

      <div
        :for={%{growing_area: bed, groups: groups} <- @free_squares}
        class="border-b border-base-300 last:border-b-0"
      >
        <div class="flex items-baseline justify-between px-5 pt-4">
          <h3 class="text-sm font-semibold">{bed.name}</h3>
          <span class="text-xs text-base-content/45">
            {pluralize(Enum.sum(Enum.map(groups, & &1.count)), "square")} free
          </span>
        </div>

        <ul class="divide-y divide-base-300/70 px-5 py-2">
          <li
            :for={group <- groups}
            id={group_dom_id(bed, group)}
            class="flex flex-wrap items-center gap-x-4 gap-y-2 py-2.5"
          >
            <span class="w-24 shrink-0 text-lg font-semibold tabular-nums tracking-tight text-sky-700">
              {group.count}
              <span class="text-xs font-normal text-base-content/50">
                {if group.count == 1, do: "square", else: "squares"}
              </span>
            </span>

            <span class="min-w-0 flex-1 text-sm">
              <span class="font-medium">{format_date(group.start_date)}</span>
              <span class="text-base-content/50">
                → {format_short_date(group.window_end_date)} · {pluralize(
                  group.weeks_available,
                  "week"
                )} · week {group.start_week}
              </span>
            </span>

            <button
              type="button"
              phx-click="fill_block"
              phx-value-bed={bed.id}
              phx-value-from={group.start_date}
              phx-value-to={group.window_end_date}
              class="btn btn-sm btn-outline shrink-0"
            >
              <.icon name="hero-sparkles" class="size-3.5" /> Plant these squares
            </button>
          </li>
        </ul>
      </div>
    </section>
    """
  end

  @doc false
  def group_dom_id(bed, group), do: "free-#{bed.id}-#{group.start_date}-#{group.window_end_date}"

  defp total_free(free_squares) do
    free_squares
    |> Enum.flat_map(& &1.groups)
    |> Enum.map(& &1.count)
    |> Enum.sum()
    |> pluralize("square")
  end

  ## Fill sidebar

  attr :filling, :map, required: true
  attr :importing, :boolean, required: true
  attr :unsaved, :boolean, required: true

  defp fill_sidebar(assigns) do
    ~H"""
    <div class="fixed inset-0 z-40" id="fill-sidebar">
      <div class="absolute inset-0 bg-base-content/20" phx-click="close_fill" aria-hidden="true">
      </div>

      <aside class="absolute inset-y-0 right-0 flex w-full max-w-md flex-col border-l border-base-300 bg-base-100 shadow-xl">
        <header class="border-b border-base-300 px-5 py-4">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <h2 class="text-base font-semibold tracking-tight">
                Plant {pluralize(@filling.group.count, "square")}
              </h2>
              <p class="mt-0.5 text-sm text-base-content/55">
                {@filling.growing_area.name} · {format_date(@filling.group.start_date)} → {format_short_date(
                  @filling.group.window_end_date
                )}
              </p>
            </div>
            <button
              type="button"
              phx-click="close_fill"
              class="btn btn-ghost btn-sm shrink-0"
              aria-label="Close"
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>
          <p id="fill-remaining" class="mt-2 text-sm">
            <span class="font-medium tabular-nums">{@filling.remaining}</span>
            <span class="text-base-content/55">of {@filling.group.count} still free</span>
          </p>
          <p class="mt-1 text-xs text-base-content/50">
            Only crops that can be planted and finish inside this window are listed.
          </p>
        </header>

        <div class="border-b border-base-300 px-5 py-3">
          <form phx-submit="import" class="flex gap-2">
            <input
              type="url"
              name="url"
              placeholder="Paste a plant URL to add one"
              disabled={@importing}
              autocomplete="off"
              class="input input-bordered input-sm w-full"
            />
            <button type="submit" disabled={@importing} class="btn btn-sm btn-primary shrink-0">
              <span :if={@importing} class="loading loading-spinner loading-xs"></span>
              {if @importing, do: "Reading…", else: "Add"}
            </button>
          </form>
        </div>

        <div class="min-h-0 flex-1 overflow-y-auto">
          <p :if={@filling.offered == []} class="px-5 py-10 text-center text-sm text-base-content/55">
            Nothing in your plant list can finish inside this window. Add a faster crop above.
          </p>

          <ul class="divide-y divide-base-300">
            <li :for={plant <- @filling.offered} class="flex items-center gap-3 px-5 py-3.5">
              <span class={["size-2.5 shrink-0 rounded-full", plant_color(plant.id).bg]}></span>

              <div class="min-w-0 flex-1">
                <p class="truncate text-sm font-medium">{plant.variety_name}</p>
                <p class="truncate text-xs text-base-content/55">
                  {plant.common_type} · {plant.days_to_maturity} days ·
                  fits {@filling.capacities[plant.id]} here
                </p>
                <p class="truncate text-xs text-base-content/40">
                  {Map.get(@filling.garden_totals, plant.id, 0)} in the garden
                </p>
              </div>

              <div class="flex shrink-0 items-center gap-1">
                <button
                  type="button"
                  phx-click="step_block_quantity"
                  phx-value-plant-id={plant.id}
                  phx-value-by="-1"
                  disabled={Map.get(@filling.quantities, plant.id, 0) == 0}
                  class="btn btn-xs btn-ghost"
                  aria-label={"One fewer #{plant.variety_name}"}
                >
                  <.icon name="hero-minus" class="size-3.5" />
                </button>
                <form phx-change="set_block_quantity" id={"block-qty-#{plant.id}"}>
                  <input type="hidden" name="plant-id" value={plant.id} />
                  <input
                    type="number"
                    name="quantity"
                    value={Map.get(@filling.quantities, plant.id, 0)}
                    min="0"
                    class="input input-bordered input-xs w-14 text-center"
                    aria-label={"How many #{plant.variety_name} here"}
                  />
                </form>
                <button
                  type="button"
                  phx-click="step_block_quantity"
                  phx-value-plant-id={plant.id}
                  phx-value-by="1"
                  disabled={
                    Map.get(@filling.quantities, plant.id, 0) >= @filling.capacities[plant.id]
                  }
                  class="btn btn-xs btn-ghost"
                  aria-label={"One more #{plant.variety_name}"}
                >
                  <.icon name="hero-plus" class="size-3.5" />
                </button>
              </div>
            </li>
          </ul>
        </div>

        <footer class="border-t border-base-300 px-5 py-3">
          <p :if={@unsaved} id="fill-unsaved" class="mb-2 text-xs text-base-content/55">
            The schedule updates when you're done.
          </p>
          <button
            type="button"
            phx-click="close_fill"
            phx-disable-with="Updating schedule…"
            class="btn btn-sm btn-block"
          >
            Done
          </button>
        </footer>
      </aside>
    </div>
    """
  end

  ## Week navigation

  attr :schedule, :any, required: true
  attr :week, :integer, required: true
  attr :activity, :map, required: true
  attr :week_1_start_date, Date, required: true

  defp week_scrubber(assigns) do
    ~H"""
    <div class="mt-6 rounded-2xl border border-base-300 bg-base-100 p-4">
      <div class="flex items-center gap-3">
        <button
          type="button"
          phx-click="step_week"
          phx-value-by="-1"
          disabled={@week == 1}
          class="btn btn-sm btn-ghost"
          aria-label="Previous week"
        >
          <.icon name="hero-chevron-left" class="size-4" />
        </button>

        <div class="min-w-0 flex-1 text-center">
          <p class="text-lg font-semibold tracking-tight">
            Week of {format_date(Date.add(@week_1_start_date, (@week - 1) * 7))}
          </p>
          <p class="text-xs text-base-content/50">
            Week {@week} of {@schedule.week_count}
          </p>
        </div>

        <button
          type="button"
          phx-click="step_week"
          phx-value-by="1"
          disabled={@week == @schedule.week_count}
          class="btn btn-sm btn-ghost"
          aria-label="Next week"
        >
          <.icon name="hero-chevron-right" class="size-4" />
        </button>
      </div>

      <div id="week-scrubber" class="mt-4 flex gap-0.5 overflow-x-auto pb-1">
        <button
          :for={week <- 1..@schedule.week_count}
          type="button"
          phx-click="select_week"
          phx-value-week={week}
          title={"Week #{week} — #{format_short_date(Date.add(@week_1_start_date, (week - 1) * 7))}"}
          class={[
            "group flex min-w-6 flex-1 flex-col items-center gap-1 rounded py-1 transition",
            week == @week && "bg-emerald-600/10",
            week != @week && "hover:bg-base-200"
          ]}
        >
          <span class={[
            "h-8 w-full rounded-sm transition",
            tick_class(@activity[week], week == @week)
          ]}>
          </span>
          <span class={[
            "text-[10px] tabular-nums",
            if(week == @week, do: "font-semibold text-emerald-700", else: "text-base-content/40")
          ]}>
            {week}
          </span>
        </button>
      </div>
    </div>
    """
  end

  defp tick_class(nil, _selected), do: "bg-base-200"

  defp tick_class(%{planted: planted, opened: opened}, selected) do
    cond do
      planted > 0 and selected -> "bg-emerald-600"
      planted > 0 -> "bg-emerald-500/70 group-hover:bg-emerald-500"
      opened > 0 -> "bg-sky-300/60 group-hover:bg-sky-400"
      true -> "bg-base-200"
    end
  end

  ## The grid

  attr :area, :map, required: true
  attr :plants_by_unit, :map, required: true
  attr :planted, :list, required: true

  defp bed_grid(assigns) do
    assigns =
      assign(assigns, :planted_ids, MapSet.new(assigns.planted, & &1.garden_plant_id))

    ~H"""
    <section class="rounded-2xl border border-base-300 bg-base-100 p-5">
      <div class="flex items-baseline justify-between">
        <h2 class="text-base font-semibold tracking-tight">{@area.name}</h2>
        <p class="text-sm text-base-content/50">
          {occupied_count(@area)} of {square_count(@area)} squares in use
        </p>
      </div>

      <div class="mt-4 overflow-x-auto">
        <div
          class="grid w-fit gap-0.5 rounded-lg bg-base-300/60 p-0.5"
          style={"grid-template-columns: repeat(#{cols(@area)}, minmax(0, 1fr))"}
        >
          <div
            :for={{cell, index} <- Enum.with_index(Enum.concat(@area.squares))}
            title={cell_title(cell, @plants_by_unit)}
            class={[
              "relative flex size-9 items-center justify-center rounded-[3px] text-[9px] font-medium leading-none transition",
              cell == [] && "bg-base-100 text-base-content/20",
              cell != [] && cell_class(cell, @plants_by_unit, @planted_ids)
            ]}
            id={"#{@area.id}-#{index}"}
          >
            <span :if={cell == []} aria-hidden="true">·</span>
            <span :if={cell != []} class="px-0.5 text-center">
              {cell_label(cell)}
            </span>
            <span
              :if={cell != [] and Enum.any?(cell, &MapSet.member?(@planted_ids, &1))}
              class="absolute -right-px -top-px size-1.5 rounded-full bg-white ring-1 ring-emerald-700"
              title="Planted this week"
            >
            </span>
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp cols(%{squares: []}), do: 1
  defp cols(%{squares: [row | _]}), do: length(row)
  defp square_count(area), do: area.squares |> Enum.concat() |> length()
  defp occupied_count(area), do: area.squares |> Enum.concat() |> Enum.count(&(&1 != []))

  defp cell_class(cell, plants_by_unit, planted_ids) do
    plant = cell |> List.first() |> then(&Map.get(plants_by_unit, &1))
    color = if plant, do: plant_color(plant.id).soft, else: "bg-base-200"

    ring =
      if Enum.any?(cell, &MapSet.member?(planted_ids, &1)),
        do: "ring-1 ring-emerald-600",
        else: ""

    [color, "border", ring]
  end

  # A square holding several small plants says how many; a single occupant needs no label, since
  # its colour already identifies it and the tooltip names it.
  defp cell_label([_single]), do: ""
  defp cell_label(cell), do: "×#{length(cell)}"

  defp cell_title([], _plants_by_unit), do: "Empty"

  defp cell_title(cell, plants_by_unit) do
    cell
    |> Enum.map(&Map.get(plants_by_unit, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies_by(& &1.variety_name)
    |> Enum.map_join(", ", fn
      {name, 1} -> name
      {name, n} -> "#{n} × #{name}"
    end)
  end

  ## Side panels

  attr :planted, :list, required: true
  attr :cleared, :list, required: true
  attr :free_blocks, :list, required: true
  attr :week, :integer, required: true

  defp week_activity_panel(assigns) do
    ~H"""
    <section class="rounded-2xl border border-base-300 bg-base-100 p-5">
      <h2 class="text-base font-semibold tracking-tight">This week</h2>

      <div class="mt-4 space-y-4 text-sm">
        <div>
          <p class="flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide text-base-content/50">
            <.icon name="hero-arrow-down-tray" class="size-3.5" /> Plant
          </p>
          <p :if={@planted == []} class="mt-1.5 text-base-content/50">Nothing to plant.</p>
          <ul :if={@planted != []} class="mt-1.5 space-y-1">
            <li :for={{name, count} <- group_by_variety(@planted)} class="flex justify-between gap-3">
              <span class="truncate">{name}</span>
              <span class="shrink-0 tabular-nums text-base-content/60">×{count}</span>
            </li>
          </ul>
        </div>

        <div class="border-t border-base-300 pt-4">
          <p class="flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide text-base-content/50">
            <.icon name="hero-scissors" class="size-3.5" /> Pull &amp; clear
          </p>
          <p :if={@cleared == []} class="mt-1.5 text-base-content/50">Nothing comes out.</p>
          <ul :if={@cleared != []} class="mt-1.5 space-y-1">
            <li :for={{name, count} <- group_by_variety(@cleared)} class="flex justify-between gap-3">
              <span class="truncate">{name}</span>
              <span class="shrink-0 tabular-nums text-base-content/60">×{count}</span>
            </li>
          </ul>
        </div>

        <div class="border-t border-base-300 pt-4">
          <p class="flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide text-base-content/50">
            <.icon name="hero-sparkles" class="size-3.5" /> Squares opening up
          </p>
          <p :if={@free_blocks == []} class="mt-1.5 text-base-content/50">
            No new planting blocks start this week.
          </p>
          <div :if={@free_blocks != []} class="mt-1.5">
            <p class="text-2xl font-semibold tabular-nums tracking-tight text-sky-700">
              {length(@free_blocks)}
            </p>
            <p class="text-xs text-base-content/55">
              {pluralize(length(@free_blocks), "square")} free for 5+ weeks
            </p>
            <ul class="mt-2 space-y-0.5 text-xs text-base-content/60">
              <li :for={{weeks, count} <- duration_breakdown(@free_blocks)}>
                {count} × {pluralize(weeks, "week")} available
              </li>
            </ul>
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :legend, :list, required: true

  defp legend_panel(assigns) do
    ~H"""
    <section class="rounded-2xl border border-base-300 bg-base-100 p-5">
      <h2 class="text-base font-semibold tracking-tight">Plants</h2>
      <ul class="mt-3 space-y-2 text-sm">
        <li :for={plant <- @legend} class="flex items-center gap-2.5">
          <span class={["size-3 shrink-0 rounded-sm", plant_color(plant.id).bg]}></span>
          <span class="truncate">{plant.variety_name}</span>
          <span class="ml-auto shrink-0 text-xs text-base-content/45">{plant.common_type}</span>
        </li>
      </ul>
    </section>
    """
  end

  defp group_by_variety(assignments) do
    assignments
    |> Enum.frequencies_by(& &1.garden_plant.plant.variety_name)
    |> Enum.sort()
  end

  defp duration_breakdown(blocks) do
    blocks |> Enum.frequencies_by(& &1.weeks_available) |> Enum.sort(:desc)
  end
end
