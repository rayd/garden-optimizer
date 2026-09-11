defmodule GardenOptimizer.FrostTest do
  use ExUnit.Case, async: true

  alias GardenOptimizer.Frost

  # Recorded from the live API, so the parser is tested against the real response shape.
  @recorded File.read!("test/support/fixtures/frost_27516.json")

  defp stub_json(body, status \\ 200) do
    Req.Test.stub(GardenOptimizer.FrostStub, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(status, body)
    end)
  end

  describe "season_dates/2" do
    test "reads the 50% column for both frosts" do
      stub_json(@recorded)

      assert {:ok, dates} = Frost.season_dates("27516", ~D[2027-01-15])
      assert dates.last_frost_date == ~D[2027-03-31]
      assert dates.first_frost_date == ~D[2027-11-03]
    end

    test "planning in the fall targets next spring, and the frost that closes that season" do
      stub_json(@recorded)

      # Today is past this year's fall frost, so the next season starts in 2027.
      assert {:ok, dates} = Frost.season_dates("27516", ~D[2026-09-10])
      assert dates.last_frost_date == ~D[2027-03-31]
      assert dates.first_frost_date == ~D[2027-11-03]
    end

    test "the day of the last frost still belongs to the season it opens" do
      stub_json(@recorded)

      assert {:ok, dates} = Frost.season_dates("27516", ~D[2027-03-31])
      assert dates.last_frost_date == ~D[2027-03-31]
    end

    test "the day after the last frost rolls the season to next year" do
      stub_json(@recorded)

      assert {:ok, dates} = Frost.season_dates("27516", ~D[2027-04-01])
      assert dates.last_frost_date == ~D[2028-03-31]
      assert dates.first_frost_date == ~D[2028-11-03]
    end

    test "both frost dates always land in the same year, so the season never inverts" do
      stub_json(@recorded)

      for today <- [~D[2026-01-01], ~D[2026-06-15], ~D[2026-12-31], ~D[2027-03-30]] do
        assert {:ok, dates} = Frost.season_dates("27516", today)
        assert dates.last_frost_date.year == dates.first_frost_date.year
        assert Date.compare(dates.first_frost_date, dates.last_frost_date) == :gt
      end
    end

    test "an unknown zip code is reported as such" do
      stub_json(~s({"error":"not found"}), 404)

      assert {:error, :zip_not_found} = Frost.season_dates("00000", ~D[2026-09-10])
    end

    test "a response missing the 50% column is not silently accepted" do
      stub_json(~s({"data":{"frost_dates":{"last_frost_32f":{"10%":"04/14"}}}}))

      assert {:error, :zip_not_found} = Frost.season_dates("27516", ~D[2026-09-10])
    end

    test "an upstream outage is distinguishable from a bad zip" do
      stub_json(~s({"error":"boom"}), 500)

      assert {:error, :unavailable} = Frost.season_dates("27516", ~D[2026-09-10])
    end

    test "a transport failure is reported as unavailable" do
      Req.Test.stub(GardenOptimizer.FrostStub, &Req.Test.transport_error(&1, :econnrefused))

      assert {:error, :unavailable} = Frost.season_dates("27516", ~D[2026-09-10])
    end
  end
end
