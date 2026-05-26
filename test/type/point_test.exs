# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Type.PointTest do
  @moduledoc """
  End-to-end round-trip of a Point-typed attribute through the data layer:
  Ash.create! → Neo4j → Ash.get! preserves the %Geo.Point{} struct.
  Verifies the symmetric split — primary stored as RFC 7946 GeoJSON STRING
  at `<attr>.json` + native Neo4j POINT companion at `<attr>.point`.

  Place.location is declared as `AshGeo.GeoJson, constraints: [geo_types:
  :point, force_srid: 4326]`. The data layer auto-promotes Geo.Point
  values via promote_geo/3 — no AshNeo4j-side type module needed.
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

  describe "constraint validation via AshGeo" do
    test "rejects non-Point Geo geometry when geo_types: :point is set" do
      line = %Geo.LineString{coordinates: [{0.0, 0.0}, {1.0, 1.0}], srid: 4326}

      assert {:error, _} =
               Place
               |> Ash.Changeset.for_create(:create, %{name: "Wrong geometry", location: line})
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
