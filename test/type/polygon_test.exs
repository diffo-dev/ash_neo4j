# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Type.PolygonTest do
  @moduledoc """
  End-to-end round-trip of a Polygon-typed attribute through the data
  layer. Place.bounds is declared as `AshGeo.GeoJson, constraints:
  [geo_types: [:polygon], force_srid: 4326]`. The data layer's
  promote_geo/3 writes the RFC 7946 GeoJSON STRING canonical at
  `bounds.json` plus scalar bbSW/bbNE Point companions for indexed
  bbox prefilter.

  This file used to be box_test.exs — Box was retired in #274 as
  storage-redundant with axis-aligned Polygon. Callers wanting
  axis-aligned validation now apply it at the application layer.
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

  defp sydney_polygon do
    %Geo.Polygon{
      coordinates: [
        # RFC 7946 closes the ring: last vertex == first vertex
        [{151.0, -34.0}, {151.5, -34.0}, {151.5, -33.5}, {151.0, -33.5}, {151.0, -34.0}]
      ],
      srid: 4326
    }
  end

  describe "round-trip through the data layer" do
    test "WGS-84 2D Polygon survives create + read" do
      poly = sydney_polygon()

      created = Place |> Ash.create!(%{name: "Sydney bbox", bounds: poly})
      assert created.bounds == poly

      reloaded = Place |> Ash.get!(created.id)
      assert reloaded.bounds == poly
    end

    test "nil bounds is preserved" do
      created = Place |> Ash.create!(%{name: "No bbox"})
      assert created.bounds == nil

      reloaded = Place |> Ash.get!(created.id)
      assert reloaded.bounds == nil
    end

    test "on disk: bounds.json (canonical) + bounds.bbSW / bounds.bbNE companions" do
      poly = sydney_polygon()
      created = Place |> Ash.create!(%{name: "Sydney bbox", bounds: poly})

      {:ok, response} =
        Sandbox.run(
          "MATCH (n:SRM:Place {uuid: $uuid}) RETURN keys(n) AS keys, n.`bounds.json` AS json, n.`bounds.bbSW` AS bb_sw, n.`bounds.bbNE` AS bb_ne",
          %{"uuid" => created.id}
        )

      [row] = response.results
      keys = row["keys"]

      assert "bounds.json" in keys
      assert "bounds.bbSW" in keys
      assert "bounds.bbNE" in keys
      refute "bounds" in keys

      assert row["json"] =~ ~s("type":"Polygon")
      assert %Bolty.Types.Point{srid: 4326, x: 151.0, y: -34.0} = row["bb_sw"]
      assert %Bolty.Types.Point{srid: 4326, x: 151.5, y: -33.5} = row["bb_ne"]
    end
  end

  describe "constraint validation via AshGeo" do
    test "rejects non-Polygon Geo geometry when geo_types: [:polygon] is set" do
      pt = %Geo.Point{coordinates: {151.21, -33.87}, srid: 4326}

      assert {:error, _} =
               Place
               |> Ash.Changeset.for_create(:create, %{name: "Wrong geometry", bounds: pt})
               |> Ash.create()
    end

    test "rejects non-Geo input" do
      assert {:error, _} =
               Place
               |> Ash.Changeset.for_create(:create, %{name: "Bad type", bounds: %{sw: 1, ne: 2}})
               |> Ash.create()
    end
  end
end
