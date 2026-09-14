defmodule GardenOptimizerWeb.FillBlockLiveTest do
  @moduledoc """
  Filling free planting squares from the schedule view.
  """
  use GardenOptimizerWeb.ConnCase, async: true

  import GardenOptimizer.Fixtures
  import Phoenix.LiveViewTest

  alias GardenOptimizer.{Gardens, Scheduling}

  setup %{conn: conn} do
    scope = visitor_scope()
    conn = visitor_conn(conn, scope)
    garden = garden_fixture(scope, name: "Backyard")
    bed = growing_area_fixture(garden, name: "Bed 1", width_in: 48, length_in: 96)

    radish =
      plant_fixture(
        variety_name: "Cherry Belle",
        common_type: "radish",
        sq_in: 36,
        harvest_type: :once,
        days_to_maturity: 28,
        anchor_offset_weeks_min: 0,
        anchor_offset_weeks_max: 0
      )

    {:ok, 4} = Gardens.set_plant_quantity(garden, radish, 4)
    {:ok, schedule} = Scheduling.build(garden)

    {:ok, view, _html} = live(conn, ~p"/gardens/#{garden}/schedule")
    %{conn: conn, scope: scope, garden: garden, bed: bed, schedule: schedule, view: view}
  end

  # The four squares the radishes vacate part-way through — a bounded opportunity, unlike the
  # season-long group, which makes the capacity assertions legible.
  defp open_reclaimed(view, garden, bed) do
    open_group(view, bed, reclaimed_group(garden))
  end

  defp open_group(view, bed, group) do
    view
    |> element("##{GardenOptimizerWeb.ScheduleLive.Show.group_dom_id(bed, group)} button")
    |> render_click()
  end

  # The group whose squares free up mid-season, found by the date it opens rather than a week
  # number, which shifts whenever the plant list changes.
  defp reclaimed_group(garden) do
    groups =
      garden
      |> Scheduling.get_schedule()
      |> Scheduling.free_squares_by_bed()
      |> Enum.flat_map(& &1.groups)

    Enum.min_by(groups, & &1.count)
  end

  defp block_count(garden, plant, group) do
    garden |> Gardens.list_garden_plants() |> Scheduling.block_unit_count(plant, group)
  end

  defp quick_crop(attrs \\ []) do
    plant_fixture(
      Keyword.merge(
        [
          variety_name: "Buttercrunch",
          common_type: "lettuce",
          sq_in: 36,
          harvest_type: :once,
          days_to_maturity: 35,
          anchor_offset_weeks_min: -4,
          anchor_offset_weeks_max: 30
        ],
        attrs
      )
    )
  end

  test "the button opens a sidebar scoped to that bed and window", %{
    view: view,
    bed: bed,
    garden: garden
  } do
    quick_crop()
    html = open_reclaimed(view, garden, bed)

    assert html =~ "Plant 4 squares"
    assert html =~ "Bed 1"
    assert html =~ "Buttercrunch"
  end

  test "only crops that finish inside the window are offered", %{
    view: view,
    bed: bed,
    garden: garden
  } do
    quick_crop()

    plant_fixture(
      variety_name: "Slowpoke",
      common_type: "pumpkin",
      sq_in: 36,
      harvest_type: :once,
      days_to_maturity: 400,
      anchor_offset_weeks_min: -4,
      anchor_offset_weeks_max: 30
    )

    html = open_reclaimed(view, garden, bed)

    assert html =~ "Buttercrunch"
    refute html =~ "Slowpoke"
  end

  test "a continuous harvester is withheld from a window something else reclaims",
       %{view: view, bed: bed, garden: garden, scope: scope} do
    quick_crop()

    basil =
      plant_fixture(
        variety_name: "Genovese",
        common_type: "basil",
        sq_in: 36,
        harvest_type: :continuous,
        anchor_offset_weeks_min: -4,
        anchor_offset_weeks_max: 30
      )

    # The week-6 group runs to first frost, so basil *is* offered there.
    assert open_reclaimed(view, garden, bed) =~ "Genovese"

    # Give the bed something that reclaims those squares mid-season, closing the window early.
    late =
      plant_fixture(
        variety_name: "Latecomer",
        common_type: "kale",
        sq_in: 324,
        harvest_type: :continuous,
        anchor_offset_weeks_min: 12,
        anchor_offset_weeks_max: 12
      )

    {:ok, 4} = Gardens.set_plant_quantity(garden, late, 4)
    {:ok, _} = Scheduling.build(garden)

    # The squares the kale will claim are now free only until it goes in — a truncated window.
    {:ok, view2, _} = live(visitor_conn(build_conn(), scope), ~p"/gardens/#{garden}/schedule")

    truncated =
      garden
      |> Scheduling.get_schedule()
      |> Scheduling.free_squares_by_bed()
      |> Enum.flat_map(& &1.groups)
      |> Enum.reject(&(&1.window_end_date == garden.first_frost_date))
      |> Enum.max_by(& &1.count)

    html = open_group(view2, bed, truncated)

    refute html =~ "Genovese"
    assert basil.harvest_type == :continuous
  end

  test "setting a quantity plants into the bed, and Done shrinks the free squares",
       %{view: view, bed: bed, garden: garden, schedule: before_schedule} do
    lettuce = quick_crop()
    group = reclaimed_group(garden)
    open_group(view, bed, group)

    html =
      view
      |> element(~s{#block-qty-#{lettuce.id}})
      |> render_change(%{"plant-id" => lettuce.id, "quantity" => "4"})

    # Sidebar stays open and counts the squares as taken, but nothing is rebuilt yet: the group is
    # still in the list behind it.
    assert html =~ "Buttercrunch"
    assert view |> element("#fill-remaining") |> render() =~ ~r/>\s*0\s*</
    assert html =~ GardenOptimizerWeb.ScheduleLive.Show.group_dom_id(bed, group)
    assert has_element?(view, "#fill-unsaved")
    assert Scheduling.get_schedule(garden).id == before_schedule.id

    html =
      view |> element(~s{#fill-sidebar footer button[phx-click="close_fill"]}) |> render_click()

    refute html =~ GardenOptimizerWeb.ScheduleLive.Show.group_dom_id(bed, group)

    schedule = Scheduling.get_schedule(garden)
    refute schedule.id == before_schedule.id
    placed = Enum.filter(schedule.assignments, &(&1.garden_plant.plant_id == lettuce.id))

    assert length(placed) == 4
    assert Enum.all?(placed, &(&1.growing_area_id == bed.id))
  end

  test "the stepper adds one at a time and reports the garden-wide total",
       %{bed: bed, garden: garden, scope: scope} do
    lettuce = quick_crop()
    {:ok, 5} = Gardens.set_plant_quantity(garden, lettuce, 5)

    {:ok, view, _} = live(visitor_conn(build_conn(), scope), ~p"/gardens/#{garden}/schedule")
    group = reclaimed_group(garden)
    html = open_group(view, bed, group)

    # Units chosen at the workbench show as a garden total, not as this block's count.
    assert html =~ "5 in the garden"

    html =
      view
      |> element(
        ~s{button[phx-click="step_block_quantity"][phx-value-plant-id="#{lettuce.id}"][phx-value-by="1"]}
      )
      |> render_click()

    assert html =~ "6 in the garden"
    assert block_count(garden, lettuce, group) == 1
  end

  test "stepping one at a time fills every square, and the last can still be taken back",
       %{view: view, bed: bed, garden: garden} do
    lettuce = quick_crop()
    group = reclaimed_group(garden)
    open_group(view, bed, group)

    plus =
      ~s{button[phx-click="step_block_quantity"][phx-value-plant-id="#{lettuce.id}"][phx-value-by="1"]}

    minus =
      ~s{button[phx-click="step_block_quantity"][phx-value-plant-id="#{lettuce.id}"][phx-value-by="-1"]}

    for left <- 3..0//-1 do
      view |> element(plus) |> render_click()
      assert view |> element("#fill-remaining") |> render() =~ ~r/>\s*#{left}\s*</
    end

    assert block_count(garden, lettuce, group) == 4
    assert view |> has_element?(plus <> "[disabled]")

    # The sidebar still owns those four units, so the last can be stepped back down.
    view |> element(minus) |> render_click()
    assert block_count(garden, lettuce, group) == 3
    assert view |> element("#fill-remaining") |> render() =~ ~r/>\s*1\s*</
  end

  test "the space in those squares cannot be exceeded", %{view: view, bed: bed, garden: garden} do
    lettuce = quick_crop()
    open_reclaimed(view, garden, bed)

    html =
      view
      |> element(~s{#block-qty-#{lettuce.id}})
      |> render_change(%{"plant-id" => lettuce.id, "quantity" => "5"})

    assert html =~ "at most 4"
    assert block_count(garden, lettuce, reclaimed_group(garden)) == 0
  end

  test "a crop too large for the group says so plainly", %{view: view, bed: bed, garden: garden} do
    quick_crop()
    # 3x3 block into a 4-square opening.
    tomato =
      plant_fixture(
        variety_name: "Beefsteak",
        common_type: "tomato",
        sq_in: 324,
        harvest_type: :once,
        days_to_maturity: 35,
        anchor_offset_weeks_min: -4,
        anchor_offset_weeks_max: 30
      )

    open_reclaimed(view, garden, bed)

    html =
      view
      |> element(~s{#block-qty-#{tomato.id}})
      |> render_change(%{"plant-id" => tomato.id, "quantity" => "1"})

    assert html =~ "needs more room than these 4 squares"
  end

  test "closing puts the sidebar away", %{view: view, bed: bed, garden: garden} do
    quick_crop()
    assert open_reclaimed(view, garden, bed) =~ "Plant 4 squares"

    html =
      view |> element(~s{#fill-sidebar footer button[phx-click="close_fill"]}) |> render_click()

    refute html =~ "Plant 4 squares"
  end

  test "closing with nothing changed doesn't rebuild",
       %{view: view, bed: bed, garden: garden, schedule: schedule} do
    quick_crop()
    open_reclaimed(view, garden, bed)

    view |> element(~s{#fill-sidebar footer button[phx-click="close_fill"]}) |> render_click()

    assert Scheduling.get_schedule(garden).id == schedule.id
  end

  test "dismissing the sidebar another way still saves",
       %{view: view, bed: bed, garden: garden, schedule: schedule} do
    lettuce = quick_crop()
    open_reclaimed(view, garden, bed)

    view
    |> element(~s{#block-qty-#{lettuce.id}})
    |> render_change(%{"plant-id" => lettuce.id, "quantity" => "2"})

    view |> element(~s{#fill-sidebar button[aria-label="Close"]}) |> render_click()

    rebuilt = Scheduling.get_schedule(garden)
    refute rebuilt.id == schedule.id
    assert Enum.count(rebuilt.assignments, &(&1.garden_plant.plant_id == lettuce.id)) == 2
  end
end
