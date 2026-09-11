defmodule GardenOptimizerWeb.VisitorAccessTest do
  @moduledoc """
  The two things standing between a public deployment and other people's gardens: a per-browser
  visitor token, and a shared access code gating the whole site.
  """
  use GardenOptimizerWeb.ConnCase, async: false

  import GardenOptimizer.Fixtures
  import Phoenix.LiveViewTest

  alias GardenOptimizer.Gardens
  alias GardenOptimizerWeb.Plugs.AccessCode

  describe "visitor identity" do
    test "a first-time visitor is given a token", %{conn: conn} do
      conn = get(conn, ~p"/")

      token = Plug.Conn.get_session(conn, "visitor_token")
      assert is_binary(token)
      assert GardenOptimizer.Visitors.valid_token?(token)
    end

    test "a returning visitor keeps theirs", %{conn: conn} do
      scope = visitor_scope()
      conn = conn |> visitor_conn(scope) |> get(~p"/")

      assert Plug.Conn.get_session(conn, "visitor_token") == scope.token
    end

    test "a tampered token is replaced rather than used", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{"visitor_token" => "not-a-real-token"})
        |> get(~p"/")

      refute Plug.Conn.get_session(conn, "visitor_token") == "not-a-real-token"
      assert GardenOptimizer.Visitors.valid_token?(Plug.Conn.get_session(conn, "visitor_token"))
    end

    test "only the hash of a token is stored" do
      scope = visitor_scope()
      garden = garden_fixture(scope, name: "Backyard")

      assert garden.visitor_hash != scope.token
      assert garden.visitor_hash == GardenOptimizer.Visitors.hash_token(scope.token)
      # A dump of the gardens table is not a set of working credentials.
      refute String.contains?(garden.visitor_hash, scope.token)
    end
  end

  describe "garden isolation" do
    setup do
      alice = visitor_scope()
      bob = visitor_scope()
      %{alice: alice, bob: bob, garden: garden_fixture(alice, name: "Alice's plot")}
    end

    test "one visitor's gardens are invisible to another", %{
      alice: alice,
      bob: bob,
      garden: garden
    } do
      assert [%{id: id}] = Gardens.list_gardens(alice)
      assert id == garden.id
      assert Gardens.list_gardens(bob) == []
    end

    test "fetching someone else's garden is a 404, not a 403", %{bob: bob, garden: garden} do
      # Indistinguishable from a garden that does not exist, so the response cannot be used to
      # confirm that an id is real.
      assert_raise Ecto.NoResultsError, fn -> Gardens.get_garden!(bob, garden.id) end
    end

    test "the index shows only your own gardens", %{conn: conn, bob: bob} do
      {:ok, _view, html} = live(visitor_conn(conn, bob), ~p"/")

      refute html =~ "Alice&#39;s plot"
      assert html =~ "No gardens yet"
    end

    test "opening someone else's garden by id fails", %{conn: conn, bob: bob, garden: garden} do
      assert_raise Ecto.NoResultsError, fn ->
        live(visitor_conn(conn, bob), ~p"/gardens/#{garden}")
      end
    end

    test "its schedule is equally out of reach", %{conn: conn, bob: bob, garden: garden} do
      assert_raise Ecto.NoResultsError, fn ->
        live(visitor_conn(conn, bob), ~p"/gardens/#{garden}/schedule")
      end
    end

    test "a bed cannot be deleted through someone else's garden", %{
      alice: alice,
      bob: bob,
      garden: garden
    } do
      bed = growing_area_fixture(garden, name: "Bed 1")

      assert_raise Ecto.NoResultsError, fn -> Gardens.get_growing_area!(bob, bed.id) end
      assert Gardens.get_growing_area!(alice, bed.id).id == bed.id
    end

    test "a new garden belongs to whoever created it", %{conn: conn} do
      scope = visitor_scope()

      Req.Test.stub(GardenOptimizer.FrostStub, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, File.read!("test/support/fixtures/frost_27516.json"))
      end)

      {:ok, view, _html} = live(visitor_conn(conn, scope), ~p"/gardens/new")
      Req.Test.allow(GardenOptimizer.FrostStub, self(), view.pid)

      view |> form("#garden-form", garden: %{name: "Mine", zip_code: "27516"}) |> render_submit()

      assert [%{name: "Mine"}] = Gardens.list_gardens(scope)
      assert Gardens.list_gardens(visitor_scope()) == []
    end
  end

  describe "access code" do
    setup do
      Application.put_env(:garden_optimizer, :access_code, "let-me-in")
      on_exit(fn -> Application.put_env(:garden_optimizer, :access_code, nil) end)
      :ok
    end

    test "the site is closed without the code", %{conn: conn} do
      conn = get(conn, ~p"/")

      assert conn.status == 403
      assert conn.halted
      assert conn.resp_body =~ "This preview is private"
    end

    test "a correct code opens it and is then remembered", %{conn: conn} do
      conn = get(conn, ~p"/?access=let-me-in")

      assert redirected_to(conn) == "/"
      assert Plug.Conn.get_session(conn, "access_granted") == true

      # The session carries it from here, so no further links need the code.
      assert recycle(conn) |> get(~p"/") |> Map.get(:status) == 200
    end

    test "the code is stripped from the URL rather than left in history", %{conn: conn} do
      # Landing on a deep link keeps the destination but drops the secret, so it cannot leak
      # through Referer headers on the way to the frost or plant APIs.
      conn = get(conn, ~p"/gardens/new?access=let-me-in&foo=bar")

      to = redirected_to(conn)
      assert to =~ "/gardens/new"
      assert to =~ "foo=bar"
      refute to =~ "let-me-in"
      refute to =~ "access="
    end

    test "a wrong code is refused", %{conn: conn} do
      conn = get(conn, ~p"/?access=nope")

      assert conn.status == 403
      refute Plug.Conn.get_session(conn, "access_granted") == true
    end

    test "a code of a different length is refused without raising", %{conn: conn} do
      # secure_compare/2 raises on unequal lengths, so the guard has to come first.
      assert get(conn, ~p"/?access=x").status == 403
      assert get(conn, ~p"/?access=#{String.duplicate("y", 200)}").status == 403
    end

    test "a websocket cannot be used to route around the gate" do
      # The socket never runs the browser pipeline, so the mount hook re-checks. Asserted against
      # the hook directly because the gate stops the dead render, leaving nothing to connect from
      # — which is exactly the bypass a hand-rolled socket client would attempt.
      session = %{"visitor_token" => visitor_scope().token}

      assert {:halt, socket} =
               GardenOptimizerWeb.VisitorHook.on_mount(
                 :default,
                 %{},
                 session,
                 %Phoenix.LiveView.Socket{}
               )

      assert socket.redirected == {:redirect, %{to: "/", status: 302}}
    end

    test "a granted session passes the mount hook" do
      scope = visitor_scope()
      session = %{"visitor_token" => scope.token, "access_granted" => true}

      assert {:cont, socket} =
               GardenOptimizerWeb.VisitorHook.on_mount(
                 :default,
                 %{},
                 session,
                 %Phoenix.LiveView.Socket{}
               )

      assert socket.assigns.current_scope.hash == scope.hash
    end

    test "granted sessions pass the mount check", %{conn: conn} do
      scope = visitor_scope()

      conn =
        Plug.Test.init_test_session(conn, %{
          "visitor_token" => scope.token,
          "access_granted" => true
        })

      assert {:ok, _view, _html} = live(conn, ~p"/")
    end

    test "with no code configured the site is open", %{conn: conn} do
      Application.put_env(:garden_optimizer, :access_code, nil)

      assert get(conn, ~p"/").status == 200
      refute AccessCode.configured_code()
    end
  end
end
