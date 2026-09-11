defmodule GardenOptimizerWeb.GardenLiveTest do
  use GardenOptimizerWeb.ConnCase, async: true

  import GardenOptimizer.Fixtures
  import Phoenix.LiveViewTest

  alias GardenOptimizer.{Gardens, Scheduling}

  @frost File.read!("test/support/fixtures/frost_27516.json")

  @page """
  <html><body><h1>Cherokee Purple</h1>
  <p>Space 18 inches apart. Transplant after the last frost. 80 days. Harvest all season.</p>
  </body></html>
  """

  @extracted %{
    "variety_name" => "Cherokee Purple",
    "common_type" => "tomato",
    "sq_in" => 324,
    "planting_anchor" => "last_frost",
    "anchor_offset_weeks_min" => 0,
    "anchor_offset_weeks_max" => 2,
    "days_to_maturity" => 80,
    "harvest_type" => "continuous"
  }

  defp stub_frost(body \\ @frost, status \\ 200) do
    Req.Test.stub(GardenOptimizer.FrostStub, fn conn ->
      conn |> Plug.Conn.put_resp_content_type("application/json") |> Plug.Conn.resp(status, body)
    end)
  end

  defp stub_import(attrs \\ @extracted) do
    Req.Test.stub(GardenOptimizer.PageStub, fn conn ->
      conn |> Plug.Conn.put_resp_content_type("text/html") |> Plug.Conn.resp(200, @page)
    end)

    Req.Test.stub(GardenOptimizer.AnthropicStub, fn conn ->
      body = %{"content" => [%{"type" => "text", "text" => Jason.encode!(attrs)}]}

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(body))
    end)
  end

  # Async work in a LiveView runs in a spawned process, which needs its own stub allowance.
  defp allow_async_stubs(view) do
    for stub <- [
          GardenOptimizer.PageStub,
          GardenOptimizer.AnthropicStub,
          GardenOptimizer.FrostStub
        ] do
      Req.Test.allow(stub, self(), view.pid)
    end
  end

  describe "index" do
    test "invites you to start when there is nothing yet", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "No gardens yet"
    end

    test "lists gardens with their frost dates", %{conn: conn} do
      scope = visitor_scope()
      garden_fixture(scope, name: "Backyard")
      {:ok, _view, html} = live(visitor_conn(conn, scope), ~p"/")

      assert html =~ "Backyard"
      assert html =~ "Mar 31, 2027"
      assert html =~ "Nov 3, 2027"
    end
  end

  describe "new garden" do
    test "previews frost dates once the zip is complete", %{conn: conn} do
      stub_frost()
      {:ok, view, _html} = live(conn, ~p"/gardens/new")
      allow_async_stubs(view)

      html =
        view
        |> form("#garden-form", garden: %{name: "Backyard", zip_code: "27516"})
        |> render_change()

      assert html =~ "Looking up frost dates"

      html = render_async(view)
      assert html =~ "Mar 31, 2027"
      assert html =~ "Nov 3, 2027"
      assert html =~ "31-week growing season"
    end

    test "an incomplete zip triggers no lookup", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/gardens/new")

      html =
        view
        |> form("#garden-form", garden: %{name: "Backyard", zip_code: "275"})
        |> render_change()

      refute html =~ "Looking up frost dates"
    end

    test "creating a garden lands on its workbench", %{conn: conn} do
      stub_frost()
      scope = visitor_scope()
      {:ok, view, _html} = live(visitor_conn(conn, scope), ~p"/gardens/new")
      allow_async_stubs(view)

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> form("#garden-form", garden: %{name: "Backyard", zip_code: "27516"})
               |> render_submit()

      garden = List.first(Gardens.list_gardens(scope))
      assert to == "/gardens/#{garden.id}"
      assert garden.last_frost_date == ~D[2027-03-31]
    end

    test "an unknown zip is reported on the zip field", %{conn: conn} do
      stub_frost(~s({}), 404)
      {:ok, view, _html} = live(conn, ~p"/gardens/new")
      allow_async_stubs(view)

      html =
        view
        |> form("#garden-form", garden: %{name: "Backyard", zip_code: "00000"})
        |> render_submit()

      assert html =~ "we don&#39;t have frost dates for that zip code"
    end
  end

  describe "garden workbench" do
    setup %{conn: conn} do
      scope = visitor_scope()
      garden = garden_fixture(scope, name: "Backyard")
      %{conn: visitor_conn(conn, scope), scope: scope, garden: garden}
    end

    test "adds a bed from a preset and shows its square count", %{conn: conn, garden: garden} do
      {:ok, view, html} = live(conn, ~p"/gardens/#{garden}")
      assert html =~ "Add a raised bed to get started"

      html =
        view
        |> element(
          ~s{button[phx-click="preset_area"][phx-value-width="48"][phx-value-length="96"]}
        )
        |> render_click()

      assert html =~ "128 planting squares"
      assert html =~ "16 × 8 squares"
    end

    test "previews the grid a bed will become as you type", %{conn: conn, garden: garden} do
      {:ok, view, html} = live(conn, ~p"/gardens/#{garden}")
      assert html =~ "both dimensions step by 6"

      html =
        view
        |> form("#area-form", growing_area: %{name: "Bed 1", width_in: 48, length_in: 96})
        |> render_change()

      assert html =~ "16 × 8 squares — 128 in total"
    end

    test "a dimension that isn't a whole number of squares names the nearest sizes", %{
      conn: conn,
      garden: garden
    } do
      {:ok, view, _html} = live(conn, ~p"/gardens/#{garden}")

      html =
        view
        |> form("#area-form", growing_area: %{name: "Odd bed", width_in: 40, length_in: 96})
        |> render_change()

      assert html =~ "try 36&quot; or 42&quot;"

      # And submitting it is refused rather than silently rounded.
      html =
        view
        |> form("#area-form", growing_area: %{name: "Odd bed", width_in: 40, length_in: 96})
        |> render_submit()

      assert html =~ "must be a multiple of 6"
      assert Gardens.list_growing_areas(garden) == []
    end

    test "the dimension inputs step in whole squares", %{conn: conn, garden: garden} do
      {:ok, _view, html} = live(conn, ~p"/gardens/#{garden}")

      assert html =~ ~s(name="growing_area[width_in]")
      assert Regex.match?(~r/growing_area\[width_in\][^>]*step="6"/, html)
      assert Regex.match?(~r/growing_area\[length_in\][^>]*step="6"/, html)
    end

    test "adds a bed from the form and can remove it", %{conn: conn, garden: garden} do
      {:ok, view, _html} = live(conn, ~p"/gardens/#{garden}")

      html =
        view
        |> form("#area-form", growing_area: %{name: "Long bed", width_in: 30, length_in: 108})
        |> render_submit()

      assert html =~ "Long bed"
      assert html =~ "90 planting squares"

      area = List.first(Gardens.list_growing_areas(garden))
      html = view |> element(~s{button[phx-value-id="#{area.id}"]}) |> render_click()
      assert html =~ "0 planting squares"
    end

    test "imports a plant from a URL and shows what was read", %{conn: conn, garden: garden} do
      growing_area_fixture(garden)
      stub_import()

      {:ok, view, _html} = live(conn, ~p"/gardens/#{garden}")
      allow_async_stubs(view)

      view
      |> element("form[phx-submit='import']")
      |> render_submit(%{url: "https://seeds.test/cherokee-purple"})

      html = render_async(view)

      assert html =~ "Cherokee Purple"
      assert html =~ "3×3 squares"
      assert html =~ "80 days to harvest"
      assert html =~ "harvest continuously"
    end

    test "an import failure explains itself without losing the page", %{
      conn: conn,
      garden: garden
    } do
      growing_area_fixture(garden)

      Req.Test.stub(GardenOptimizer.PageStub, fn conn ->
        Plug.Conn.resp(conn, 500, "boom")
      end)

      {:ok, view, _html} = live(conn, ~p"/gardens/#{garden}")
      allow_async_stubs(view)

      view
      |> element("form[phx-submit='import']")
      |> render_submit(%{url: "https://seeds.test/broken"})

      assert render_async(view) =~ "Couldn&#39;t load that page"
    end

    test "quantity steppers move the capacity meter", %{conn: conn, garden: garden} do
      growing_area_fixture(garden, width_in: 48, length_in: 96)
      plant = plant_fixture(sq_in: 324)
      {:ok, 1} = Gardens.set_plant_quantity(garden, plant, 1)

      {:ok, view, html} = live(conn, ~p"/gardens/#{garden}")
      # One tomato reserves 9 of 128 squares.
      assert html =~ "7.0"

      html =
        view
        |> element(
          ~s{button[phx-click="step_quantity"][phx-value-plant-id="#{plant.id}"][phx-value-by="1"]}
        )
        |> render_click()

      assert html =~ "14.1"
      assert [{^plant, 2}] = Gardens.plant_quantities(garden)
    end

    test "typing a quantity sets it directly", %{conn: conn, garden: garden} do
      growing_area_fixture(garden, width_in: 48, length_in: 96)
      plant = plant_fixture(sq_in: 36)
      {:ok, 1} = Gardens.set_plant_quantity(garden, plant, 1)

      {:ok, view, _html} = live(conn, ~p"/gardens/#{garden}")

      view
      |> element(~s{form[phx-change="set_quantity"]})
      |> render_change(%{"plant-id" => plant.id, "quantity" => "12"})

      assert [{^plant, 12}] = Gardens.plant_quantities(garden)
    end

    test "the garden cannot be pushed past 100% full", %{conn: conn, garden: garden} do
      growing_area_fixture(garden, width_in: 12, length_in: 12)
      plant = plant_fixture(sq_in: 36)
      {:ok, 4} = Gardens.set_plant_quantity(garden, plant, 4)

      {:ok, view, html} = live(conn, ~p"/gardens/#{garden}")
      assert html =~ "100.0"

      html =
        view
        |> element(~s{form[phx-change="set_quantity"]})
        |> render_change(%{"plant-id" => plant.id, "quantity" => "5"})

      assert html =~ "past 100% full"
      assert [{^plant, 4}] = Gardens.plant_quantities(garden)
    end

    test "building requires both beds and plants", %{conn: conn, garden: garden} do
      {:ok, view, _html} = live(conn, ~p"/gardens/#{garden}")
      assert view |> element("button[phx-click='build']") |> render() =~ "disabled"
    end

    test "building navigates to the schedule", %{conn: conn, garden: garden} do
      growing_area_fixture(garden, width_in: 48, length_in: 96)
      {:ok, 2} = Gardens.set_plant_quantity(garden, plant_fixture(sq_in: 324), 2)

      {:ok, view, html} = live(conn, ~p"/gardens/#{garden}")
      assert html =~ "Build garden"

      view |> element("button[phx-click='build']") |> render_click()

      assert_redirect(view, ~p"/gardens/#{garden}/schedule")
      assert Scheduling.get_schedule(garden)
    end

    test "an existing schedule turns the button into a re-build", %{conn: conn, garden: garden} do
      growing_area_fixture(garden, width_in: 48, length_in: 96)
      {:ok, 1} = Gardens.set_plant_quantity(garden, plant_fixture(sq_in: 324), 1)
      {:ok, _schedule} = Scheduling.build(garden)

      {:ok, _view, html} = live(conn, ~p"/gardens/#{garden}")

      assert html =~ "Re-build garden"
      assert html =~ "View schedule"
    end
  end
end
