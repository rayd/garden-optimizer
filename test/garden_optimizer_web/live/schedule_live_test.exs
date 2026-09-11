defmodule GardenOptimizerWeb.ScheduleLiveTest do
  use GardenOptimizerWeb.ConnCase, async: true

  import GardenOptimizer.Fixtures
  import GardenOptimizerWeb.Format
  import Phoenix.LiveViewTest

  alias GardenOptimizer.{Gardens, Scheduling}

  setup %{conn: conn} do
    scope = visitor_scope()
    garden = garden_fixture(scope, name: "Backyard")
    bed = growing_area_fixture(garden, name: "Bed 1", width_in: 48, length_in: 96)
    %{conn: visitor_conn(conn, scope), scope: scope, garden: garden, bed: bed}
  end

  defp with_schedule(garden, plants) do
    for {plant, quantity} <- plants do
      {:ok, ^quantity} = Gardens.set_plant_quantity(garden, plant, quantity)
    end

    {:ok, schedule} = Scheduling.build(garden)
    schedule
  end

  test "sends you back to the workbench when nothing has been built", %{
    conn: conn,
    garden: garden
  } do
    assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
             live(conn, ~p"/gardens/#{garden}/schedule")

    assert to == "/gardens/#{garden.id}"
    assert flash["info"] =~ "Build the garden"
  end

  test "opens on the first week anything goes in the ground", %{conn: conn, garden: garden} do
    tomato =
      plant_fixture(
        variety_name: "Cherokee Purple",
        sq_in: 324,
        anchor_offset_weeks_min: 0,
        anchor_offset_weeks_max: 2
      )

    schedule = with_schedule(garden, [{tomato, 2}])

    {:ok, _view, html} = live(conn, ~p"/gardens/#{garden}/schedule")

    assert html =~ "Week of #{format_date(schedule.week_1_start_date)}"
    assert html =~ "Week 1 of #{schedule.week_count}"
    assert html =~ "Cherokee Purple"
  end

  test "renders one grid per bed at the right dimensions", %{conn: conn, garden: garden} do
    growing_area_fixture(garden, name: "Bed 2", width_in: 48, length_in: 48)
    with_schedule(garden, [{plant_fixture(sq_in: 324), 2}])

    {:ok, _view, html} = live(conn, ~p"/gardens/#{garden}/schedule")

    assert html =~ "Bed 1"
    assert html =~ "Bed 2"
    # 4' x 8' is 8 columns; 4' x 4' is 8 columns too, but the square counts differ.
    assert html =~ "of 128 squares in use"
    assert html =~ "of 64 squares in use"
  end

  test "a shared square shows how many plants are in it", %{conn: conn, garden: garden} do
    radish =
      plant_fixture(
        variety_name: "Cherry Belle",
        common_type: "radish",
        sq_in: 9,
        harvest_type: :continuous
      )

    with_schedule(garden, [{radish, 4}])

    {:ok, _view, html} = live(conn, ~p"/gardens/#{garden}/schedule")

    # Four radishes in one square: labelled "x4" and titled with the count.
    assert html =~ "×4"
    assert html =~ "4 × Cherry Belle"
    assert html =~ "1 of 128 squares in use"
  end

  test "walking forward a week clears a matured crop", %{conn: conn, garden: garden} do
    radish =
      plant_fixture(
        variety_name: "Cherry Belle",
        sq_in: 36,
        harvest_type: :once,
        days_to_maturity: 28,
        anchor_offset_weeks_min: 0,
        anchor_offset_weeks_max: 0
      )

    with_schedule(garden, [{radish, 1}])
    {:ok, view, html} = live(conn, ~p"/gardens/#{garden}/schedule")

    assert html =~ "1 of 128 squares in use"

    # Planted week 1, stands through week 5, gone in week 6.
    html = view |> element(~s{#week-scrubber button[phx-value-week="6"]}) |> render_click()

    assert html =~ "0 of 128 squares in use"
    assert html =~ "Cherry Belle"
    assert html =~ "Pull &amp; clear"
  end

  test "the this-week panel lists what to plant", %{conn: conn, garden: garden} do
    tomato = plant_fixture(variety_name: "Cherokee Purple", sq_in: 324)
    with_schedule(garden, [{tomato, 3}])

    {:ok, _view, html} = live(conn, ~p"/gardens/#{garden}/schedule")

    assert html =~ "Plant"
    assert html =~ "Cherokee Purple"
    assert html =~ "×3"
  end

  test "free planting blocks are counted for the selected week", %{conn: conn, garden: garden} do
    radish =
      plant_fixture(
        sq_in: 36,
        harvest_type: :once,
        days_to_maturity: 28,
        anchor_offset_weeks_min: 0,
        anchor_offset_weeks_max: 0
      )

    schedule = with_schedule(garden, [{radish, 2}])
    {:ok, view, html} = live(conn, ~p"/gardens/#{garden}/schedule")

    # Week 1: every untouched square opens a season-long block.
    assert html =~ "squares free for 5+ weeks"

    html = view |> element(~s{#week-scrubber button[phx-value-week="6"]}) |> render_click()

    # The two radish squares free up together in week 6.
    assert html =~ "2 × #{schedule.week_count - 5} weeks available"
  end

  test "stepping past the ends of the season is clamped", %{conn: conn, garden: garden} do
    schedule = with_schedule(garden, [{plant_fixture(sq_in: 324), 1}])
    {:ok, view, _html} = live(conn, ~p"/gardens/#{garden}/schedule")

    # Week 1 is the start of the season, so there is nowhere further back to go.
    assert view |> element(~s{button[phx-click="step_week"][phx-value-by="-1"]}) |> render() =~
             "disabled"

    html =
      view
      |> element(~s{#week-scrubber button[phx-value-week="#{schedule.week_count}"]})
      |> render_click()

    assert html =~ "Week #{schedule.week_count} of #{schedule.week_count}"

    # And the last week is likewise the end of the line.
    assert view |> element(~s{button[phx-click="step_week"][phx-value-by="1"]}) |> render() =~
             "disabled"

    # Stepping within the season still works in both directions.
    html = view |> element(~s{button[phx-click="step_week"][phx-value-by="-1"]}) |> render_click()
    assert html =~ "Week #{schedule.week_count - 1} of #{schedule.week_count}"
  end

  test "free squares are listed per bed with count, duration and date", %{
    conn: conn,
    garden: garden,
    bed: bed
  } do
    radish =
      plant_fixture(
        sq_in: 36,
        harvest_type: :once,
        days_to_maturity: 28,
        anchor_offset_weeks_min: 0,
        anchor_offset_weeks_max: 0
      )

    schedule = with_schedule(garden, [{radish, 2}])
    {:ok, _view, html} = live(conn, ~p"/gardens/#{garden}/schedule")

    assert html =~ "Free planting squares"
    assert html =~ bed.name
    assert html =~ "Plant these squares"

    # Two opportunities: the 126 squares nothing ever touches, and the two the radishes vacate.
    groups =
      schedule |> GardenOptimizer.Scheduling.free_squares_by_bed() |> Enum.flat_map(& &1.groups)

    assert length(groups) == 2

    for group <- groups do
      assert html =~ GardenOptimizerWeb.ScheduleLive.Show.group_dom_id(bed, group)
      assert html =~ format_date(group.start_date)
    end

    assert html =~ "#{schedule.week_count - 5} weeks"
  end

  test "plants that couldn't be placed are called out", %{conn: conn, garden: garden} do
    tomato = plant_fixture(variety_name: "Cherokee Purple", sq_in: 324, harvest_type: :continuous)
    with_schedule(garden, [{tomato, 14}])

    {:ok, _view, html} = live(conn, ~p"/gardens/#{garden}/schedule")

    assert html =~ "Some plants couldn&#39;t be placed"
    assert html =~ "no bed had room for it"
  end

  test "the legend names every variety in the schedule", %{conn: conn, garden: garden} do
    tomato = plant_fixture(variety_name: "Cherokee Purple", common_type: "tomato", sq_in: 324)
    basil = plant_fixture(variety_name: "Genovese", common_type: "basil", sq_in: 36)
    with_schedule(garden, [{tomato, 1}, {basil, 2}])

    {:ok, _view, html} = live(conn, ~p"/gardens/#{garden}/schedule")

    assert html =~ "Cherokee Purple"
    assert html =~ "Genovese"
    assert html =~ "basil"
  end
end
