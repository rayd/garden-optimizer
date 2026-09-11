defmodule GardenOptimizerWeb.ScheduleLive.Show do
  @moduledoc """
  The planting schedule, one week at a time.

  Only the selected week's grid is materialized — the full season is ~30k cells and there is no
  reason to build the other 30 weeks to render one. Dates lead the interface because week numbers
  shift whenever the plant list changes.
  """
  use GardenOptimizerWeb, :live_view

  alias GardenOptimizer.Gardens
  alias GardenOptimizer.Scheduling

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    garden = Gardens.get_garden!(id)

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
         |> assign(:free_summary, Scheduling.free_block_summary(schedule))
         |> assign(:unplaced, Scheduling.unplaced_details(schedule))
         |> assign(:legend, legend(schedule))
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
    <Layouts.app flash={@flash}>
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
          <.season_summary summary={@free_summary} week={@week} />
        </div>
      </div>
    </Layouts.app>
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

  attr :summary, :list, required: true
  attr :week, :integer, required: true

  defp season_summary(assigns) do
    ~H"""
    <section class="rounded-2xl border border-base-300 bg-base-100 p-5">
      <h2 class="text-base font-semibold tracking-tight">Free planting blocks</h2>
      <p class="mt-1 text-xs text-base-content/55">
        Squares that sit empty for five weeks or more — room for a second crop.
      </p>

      <p :if={@summary == []} class="mt-4 text-sm text-base-content/50">
        The garden is fully committed all season.
      </p>

      <ul
        :if={@summary != []}
        id="free-block-summary"
        class="mt-4 max-h-72 space-y-0.5 overflow-y-auto pr-1"
      >
        <li :for={entry <- @summary}>
          <button
            type="button"
            phx-click="select_week"
            phx-value-week={entry.week}
            class={[
              "flex w-full items-baseline justify-between gap-3 rounded-lg px-2.5 py-1.5 text-left text-sm transition",
              entry.week == @week && "bg-emerald-600/10 font-medium",
              entry.week != @week && "hover:bg-base-200"
            ]}
          >
            <span class="truncate">{format_short_date(entry.start_date)}</span>
            <span class="shrink-0 text-xs text-base-content/55">
              {entry.count} × {longest(entry.durations)}
            </span>
          </button>
        </li>
      </ul>
    </section>
    """
  end

  defp longest(durations) do
    durations |> Enum.map(&elem(&1, 0)) |> Enum.max() |> pluralize("week")
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
