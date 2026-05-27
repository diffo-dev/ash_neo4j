# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.MultiLineStringTest do
  @moduledoc """
  MultiLineString coverage (#279 #5). The sixth RFC 7946 / TMF675
  geometry type works by construction after #274 — `AshNeo4j.Util`
  round-trips it through the GeoJSON `STRING`, and `topo` handles it in
  the predicates — but it had no test fixture. The `:routes`
  MultiLineString attribute on `Place` gives these something concrete.
  """
  use ExUnit.Case, async: true

  require Ash.Query

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Functions.{StContains, StIntersects}
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Place

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  defp polygon(sw_x, sw_y, ne_x, ne_y) do
    %Geo.Polygon{
      coordinates: [[{sw_x, sw_y}, {ne_x, sw_y}, {ne_x, ne_y}, {sw_x, ne_y}, {sw_x, sw_y}]],
      srid: 4326
    }
  end

  defp routes do
    %Geo.MultiLineString{
      coordinates: [
        [{151.21, -33.87}, {151.30, -33.50}],
        [{151.60, -33.40}, {151.78, -32.93}]
      ],
      srid: 4326
    }
  end

  describe "storage round-trip" do
    test "create + read preserves the MultiLineString intact" do
      created = Place |> Ash.create!(%{name: "Dual fibre runs", routes: routes()})
      reread = Place |> Ash.get!(created.id)

      assert %Geo.MultiLineString{coordinates: coords, srid: 4326} = reread.routes

      assert coords == [
               [{151.21, -33.87}, {151.30, -33.50}],
               [{151.60, -33.40}, {151.78, -32.93}]
             ]
    end
  end

  describe "st_intersects(multilinestring, polygon) — any-of" do
    test "true when any constituent line crosses the polygon" do
      sydney = polygon(151.0, -34.0, 151.5, -33.5)
      assert {:known, true} = StIntersects.evaluate(%{arguments: [routes(), sydney]})
      assert {:known, true} = StIntersects.evaluate(%{arguments: [sydney, routes()]})
    end

    test "false when no constituent line meets the polygon" do
      perth = polygon(115.5, -32.5, 116.5, -31.5)
      assert {:known, false} = StIntersects.evaluate(%{arguments: [routes(), perth]})
    end

    test "finds places whose routes intersect a search polygon via Ash.Query" do
      sydney = Place |> Ash.create!(%{name: "Sydney routes", routes: routes()})

      _perth =
        Place
        |> Ash.create!(%{
          name: "Perth routes",
          routes: %Geo.MultiLineString{
            coordinates: [[{115.86, -31.95}, {115.90, -32.00}]],
            srid: 4326
          }
        })

      search = polygon(151.0, -34.0, 151.5, -33.5)

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_intersects(routes, ^search))
        |> Ash.read()

      ids = Enum.map(results, & &1.id)
      assert sydney.id in ids
      refute _perth.id in ids
    end
  end

  describe "st_contains(polygon, multilinestring) — all-of" do
    test "true when every constituent line lies inside the polygon" do
      big = polygon(151.0, -34.0, 152.0, -32.5)
      assert {:known, true} = StContains.evaluate(%{arguments: [big, routes()]})
    end

    test "false when any constituent line extends beyond the polygon" do
      small = polygon(151.0, -34.0, 151.5, -33.5)
      assert {:known, false} = StContains.evaluate(%{arguments: [small, routes()]})
    end
  end
end
