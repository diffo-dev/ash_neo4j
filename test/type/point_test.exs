# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Type.PointTest do
  @moduledoc """
  End-to-end round-trip of AshNeo4j.Type.Point through the data layer:
  Ash.create! → Neo4j → Ash.get! preserves the %Geo.Point{} struct.
  Verifies the symmetric split — primary stored at `<attr>.point` (native
  Neo4j POINT) + companion at `<attr>.json` (RFC 7946 GeoJSON STRING).
  """
  use ExUnit.Case, async: true

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Place

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  describe "round-trip through the data layer" do
    test "WGS-84 2D Point survives create + read" do
      sydney = %Geo.Point{coordinates: {151.2093, -33.8688}, srid: 4326}

      created = Place |> Ash.create!(%{name: "Sydney CBD", location: sydney})
      assert created.location == sydney

      reloaded = Place |> Ash.get!(created.id)
      assert reloaded.location == sydney
    end

    test "nil location is preserved" do
      created = Place |> Ash.create!(%{name: "No location"})
      assert created.location == nil

      reloaded = Place |> Ash.get!(created.id)
      assert reloaded.location == nil
    end

    test "symmetric split — node carries both location.point and location.json properties" do
      sydney = %Geo.Point{coordinates: {151.2093, -33.8688}, srid: 4326}
      created = Place |> Ash.create!(%{name: "Sydney CBD", location: sydney})

      {:ok, response} =
        Sandbox.run(
          "MATCH (n:SRM:Place {uuid: $uuid}) RETURN keys(n) AS keys, n.`location.point` AS native, n.`location.json` AS json",
          %{"uuid" => created.id}
        )

      [row] = response.results
      keys = row["keys"]

      assert "location.point" in keys
      assert "location.json" in keys
      refute "location" in keys

      assert %Bolty.Types.Point{srid: 4326, x: 151.2093, y: -33.8688} = row["native"]
      assert row["json"] =~ ~s("type":"Point")
      assert row["json"] =~ ~s("coordinates":[151.2093,-33.8688])
    end
  end

  describe "cast_input validation" do
    test "rejects non-WGS-84 srid with a clear error" do
      cartesian = %Geo.Point{coordinates: {10.0, 20.0}, srid: 0}

      assert {:error, _} =
               Place
               |> Ash.Changeset.for_create(:create, %{name: "Bad CRS", location: cartesian})
               |> Ash.create()
    end

    test "rejects non-Point input with a clear error" do
      assert {:error, _} =
               Place
               |> Ash.Changeset.for_create(:create, %{name: "Bad type", location: %{lng: 1, lat: 2}})
               |> Ash.create()
    end

    test "rejects %Bolty.Types.Point{} input (driver-layer type, smell at the Ash boundary)" do
      bolty_pt = Bolty.Types.Point.create(:wgs_84, 151.21, -33.87)

      assert {:error, _} =
               Place
               |> Ash.Changeset.for_create(:create, %{name: "Bolty input", location: bolty_pt})
               |> Ash.create()
    end
  end
end
