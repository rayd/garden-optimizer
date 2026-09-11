defmodule GardenOptimizer.Plants.ImporterTest do
  use GardenOptimizer.DataCase, async: true

  alias GardenOptimizer.Plants
  alias GardenOptimizer.Plants.Importer

  @page """
  <html>
    <head><title>Cherokee Purple Tomato</title><style>.a{color:red}</style></head>
    <body>
      <nav>Home Shop Cart Account</nav>
      <script>window.analytics = 1;</script>
      <h1>Cherokee Purple Tomato</h1>
      <p>Space plants 18 inches apart. Transplant 1 to 2 weeks after the last frost.</p>
      <p>80 days to maturity. Harvest continuously through the season.</p>
      <footer>Copyright 2027</footer>
    </body>
  </html>
  """

  @extracted %{
    "variety_name" => "Cherokee Purple",
    "common_type" => "tomato",
    "sq_in" => 324,
    "planting_anchor" => "last_frost",
    "anchor_offset_weeks_min" => 1,
    "anchor_offset_weeks_max" => 2,
    "days_to_maturity" => 80,
    "harvest_type" => "continuous"
  }

  defp stub_page(html \\ @page, status \\ 200) do
    Req.Test.stub(GardenOptimizer.PageStub, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.resp(status, html)
    end)
  end

  # Captures the outgoing request body so tests can assert on what we actually send Claude.
  defp stub_claude(attrs \\ @extracted, status \\ 200) do
    test = self()

    Req.Test.stub(GardenOptimizer.AnthropicStub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:claude_request, Jason.decode!(body), conn.req_headers})

      response = %{
        "content" => [%{"type" => "text", "text" => Jason.encode!(attrs)}],
        "model" => "claude-haiku-4-5",
        "stop_reason" => "end_turn"
      }

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(status, Jason.encode!(response))
    end)
  end

  describe "to_text/1" do
    test "keeps the growing instructions and drops the page furniture" do
      text = Importer.to_text(@page)

      assert text =~ "Space plants 18 inches apart"
      assert text =~ "80 days to maturity"
      refute text =~ "window.analytics"
      refute text =~ "color:red"
      refute text =~ "Home Shop Cart"
      refute text =~ "Copyright 2027"
    end

    test "collapses whitespace so the model isn't billed for indentation" do
      refute Importer.to_text(@page) =~ "  "
    end
  end

  describe "extract/1" do
    test "sends the page text to claude-haiku-4-5 under a JSON schema" do
      stub_page()
      stub_claude()

      assert {:ok, attrs} = Importer.extract("https://seeds.test/cherokee-purple")
      assert attrs["variety_name"] == "Cherokee Purple"
      assert attrs["source_url"] == "https://seeds.test/cherokee-purple"

      assert_received {:claude_request, body, headers}
      assert body["model"] == "claude-haiku-4-5"
      assert body["output_config"]["format"]["type"] == "json_schema"

      schema = body["output_config"]["format"]["schema"]
      assert schema["additionalProperties"] == false

      # Every field the scheduler needs must be required, including the two the original
      # field list omitted.
      assert Enum.sort(schema["required"]) ==
               Enum.sort(~w(variety_name common_type sq_in planting_anchor
                            anchor_offset_weeks_min anchor_offset_weeks_max
                            days_to_maturity harvest_type))

      assert {"anthropic-version", "2023-06-01"} in headers
      assert {"x-api-key", "test-key"} in headers

      [%{"content" => prompt}] = body["messages"]
      assert prompt =~ "Space plants 18 inches apart"
      assert prompt =~ "https://seeds.test/cherokee-purple"
      refute prompt =~ "window.analytics"
    end

    test "the prompt resolves the two ambiguities a plant page usually leaves open" do
      stub_page()
      stub_claude()

      assert {:ok, _attrs} = Importer.extract("https://seeds.test/cherokee-purple")
      assert_received {:claude_request, body, _headers}
      [%{"content" => prompt}] = body["messages"]

      # The prompt wraps for readability, so compare against it unwrapped — this is about what
      # the sentences say, not where the source happens to break them.
      unwrapped = String.replace(prompt, ~r/\s+/, " ")

      # A page usually gives both a direct-sow and a transplant date, and a spacing range rather
      # than a single number. Left unsaid, the model picks one arbitrarily and the schedule
      # shifts between imports of the same page.
      assert unwrapped =~
               "When a plant can be direct seeded or transplanted, prefer the transplanting method."

      assert unwrapped =~
               "When a plant has min/max/average spacing requirements, use the average."

      # They have to land before the field list, or they read as notes on the JSON shape.
      [guidance, fields] = String.split(unwrapped, "Structure the response as a JSON object")
      assert guidance =~ "prefer the transplanting method"
      assert guidance =~ "use the average"
      assert fields =~ "variety_name"
    end

    test "rejects anything that isn't an http(s) URL" do
      assert {:error, :invalid_url} = Importer.extract("not a url")
      assert {:error, :invalid_url} = Importer.extract("ftp://seeds.test/x")
      assert {:error, :invalid_url} = Importer.extract(nil)
    end

    test "an unreachable page is distinguishable from an unreadable one" do
      stub_page("<html></html>", 404)

      assert {:error, :page_unavailable} = Importer.extract("https://seeds.test/gone")
    end

    test "an API error surfaces as an extraction failure" do
      stub_page()
      stub_claude(@extracted, 429)

      assert {:error, :extraction_failed} = Importer.extract("https://seeds.test/x")
    end

    test "a response we can't parse is reported rather than half-applied" do
      stub_page()

      Req.Test.stub(GardenOptimizer.AnthropicStub, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"content" => [%{"type" => "text", "text" => "sorry!"}]})
        )
      end)

      assert {:error, :extraction_failed} = Importer.extract("https://seeds.test/x")
    end

    test "a missing API key is called out specifically" do
      stub_page()
      original = Application.get_env(:garden_optimizer, :anthropic)
      Application.put_env(:garden_optimizer, :anthropic, Keyword.put(original, :api_key, nil))
      on_exit(fn -> Application.put_env(:garden_optimizer, :anthropic, original) end)

      assert {:error, :missing_api_key} = Importer.extract("https://seeds.test/x")
      assert Importer.describe_error(:missing_api_key) =~ "ANTHROPIC_API_KEY"
    end
  end

  describe "Plants.import_from_url/1" do
    test "saves the extracted plant" do
      stub_page()
      stub_claude()

      assert {:ok, plant} = Plants.import_from_url("https://seeds.test/cherokee-purple")
      assert plant.variety_name == "Cherokee Purple"
      assert plant.sq_in == 324
      assert plant.planting_anchor == :last_frost
      assert plant.harvest_type == :continuous
      assert plant.days_to_maturity == 80
    end

    test "re-importing the same URL refreshes the plant instead of duplicating it" do
      stub_page()
      stub_claude()
      assert {:ok, first} = Plants.import_from_url("https://seeds.test/cherokee-purple")

      stub_claude(%{@extracted | "days_to_maturity" => 85, "sq_in" => 400})
      assert {:ok, second} = Plants.import_from_url("https://seeds.test/cherokee-purple")

      assert second.id == first.id
      assert second.days_to_maturity == 85
      assert length(Plants.list_plants()) == 1
    end

    test "nonsense values are rejected with a readable explanation" do
      stub_page()
      stub_claude(%{@extracted | "sq_in" => 0})

      assert {:error, {:invalid_plant, changeset} = error} =
               Plants.import_from_url("https://seeds.test/x")

      assert "must be greater than 0" in errors_on(changeset).sq_in
      assert Importer.describe_error(error) =~ "sq_in"
    end

    test "a window that ends before it begins is rejected" do
      stub_page()
      stub_claude(%{@extracted | "anchor_offset_weeks_min" => 4, "anchor_offset_weeks_max" => 1})

      assert {:error, {:invalid_plant, changeset}} =
               Plants.import_from_url("https://seeds.test/x")

      assert errors_on(changeset).anchor_offset_weeks_max != []
    end
  end
end
