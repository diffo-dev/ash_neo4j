# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.StIntersectsTest do
  @moduledoc """
  `st_intersects(polygon, polygon)` — true if the two polygons share any
  space (bbox intersection at v1 — over-approximates for non-axis-aligned;
  exact for axis-aligned). Evaluates in memory.
  """
  use ExUnit.Case, async: true

  require Ash.Query

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Functions.StIntersects
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
      coordinates: [
        [{sw_x, sw_y}, {ne_x, sw_y}, {ne_x, ne_y}, {sw_x, ne_y}, {sw_x, sw_y}]
      ],
      srid: 4326
    }
  end

  describe "evaluate/1" do
    test "fully overlapping polygons intersect" do
      a = polygon(0.0, 0.0, 10.0, 10.0)
      b = polygon(2.0, 2.0, 8.0, 8.0)
      assert {:known, true} = StIntersects.evaluate(%{arguments: [a, b]})
    end

    test "partially overlapping polygons intersect" do
      a = polygon(0.0, 0.0, 5.0, 5.0)
      b = polygon(3.0, 3.0, 8.0, 8.0)
      assert {:known, true} = StIntersects.evaluate(%{arguments: [a, b]})
    end

    test "edge-touching polygons intersect (inclusive boundary)" do
      a = polygon(0.0, 0.0, 5.0, 5.0)
      b = polygon(5.0, 0.0, 10.0, 5.0)
      assert {:known, true} = StIntersects.evaluate(%{arguments: [a, b]})
    end

    test "disjoint polygons do not intersect" do
      a = polygon(0.0, 0.0, 5.0, 5.0)
      b = polygon(10.0, 10.0, 15.0, 15.0)
      assert {:known, false} = StIntersects.evaluate(%{arguments: [a, b]})
    end

    test "nil arguments yield false" do
      a = polygon(0.0, 0.0, 5.0, 5.0)
      assert {:known, false} = StIntersects.evaluate(%{arguments: [nil, a]})
      assert {:known, false} = StIntersects.evaluate(%{arguments: [a, nil]})
    end
  end

  describe "st_intersects in Ash.Query.filter (in-memory)" do
    test "finds places whose bounds intersect the given polygon" do
      sydney = Place |> Ash.create!(%{name: "Sydney", bounds: polygon(151.0, -34.0, 151.5, -33.5)})
      _perth = Place |> Ash.create!(%{name: "Perth", bounds: polygon(115.5, -32.5, 116.5, -31.5)})

      overlap_with_sydney = polygon(151.2, -33.8, 152.0, -33.3)

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_intersects(bounds, ^overlap_with_sydney))
        |> Ash.read()

      ids = Enum.map(results, & &1.id)
      assert sydney.id in ids
      assert length(results) == 1
    end
  end

  describe "evaluate/1 — LineString vs Polygon (exact, via topo)" do
    test "line with a vertex inside the polygon intersects" do
      line = %Geo.LineString{
        coordinates: [{151.21, -33.87}, {151.30, -33.50}, {151.78, -32.93}],
        srid: 4326
      }

      sydney_bbox = polygon(151.0, -34.0, 151.5, -33.5)
      assert {:known, true} = StIntersects.evaluate(%{arguments: [line, sydney_bbox]})
      assert {:known, true} = StIntersects.evaluate(%{arguments: [sydney_bbox, line]})
    end

    test "line that crosses the polygon with NO vertex inside it intersects (exact edge-crossing — the old bbox approximation missed this)" do
      # Both vertices sit outside the polygon (one west, one east), but the
      # segment passes straight through it. Vertex-in-bbox would say false;
      # topo correctly says true.
      line = %Geo.LineString{coordinates: [{150.0, -33.75}, {152.0, -33.75}], srid: 4326}
      poly = polygon(151.0, -34.0, 151.5, -33.5)

      assert {:known, true} = StIntersects.evaluate(%{arguments: [line, poly]})
      assert {:known, true} = StIntersects.evaluate(%{arguments: [poly, line]})
    end

    test "line genuinely clear of the polygon does not intersect" do
      # Runs below the polygon, never crossing it.
      line = %Geo.LineString{coordinates: [{150.0, -35.0}, {152.0, -35.0}], srid: 4326}
      far_polygon = polygon(151.0, -33.0, 151.5, -32.5)
      assert {:known, false} = StIntersects.evaluate(%{arguments: [line, far_polygon]})
    end
  end

  describe "evaluate/1 — MultiPoint vs Polygon (any-of)" do
    test "multipoint with a point inside the polygon intersects" do
      pes = %Geo.MultiPoint{coordinates: [{151.21, -33.87}, {115.86, -31.95}], srid: 4326}

      sydney_bbox = polygon(151.0, -34.0, 151.5, -33.5)
      assert {:known, true} = StIntersects.evaluate(%{arguments: [pes, sydney_bbox]})
      assert {:known, true} = StIntersects.evaluate(%{arguments: [sydney_bbox, pes]})
    end

    test "multipoint with no point inside the polygon does not intersect" do
      pes = %Geo.MultiPoint{coordinates: [{115.86, -31.95}, {144.96, -37.81}], srid: 4326}

      sydney_bbox = polygon(151.0, -34.0, 151.5, -33.5)
      assert {:known, false} = StIntersects.evaluate(%{arguments: [pes, sydney_bbox]})
    end
  end

  describe "evaluate/1 — MultiPolygon vs Polygon (any-of)" do
    test "multipolygon with any constituent intersecting the polygon intersects" do
      regions = %Geo.MultiPolygon{
        coordinates: [
          [[{151.0, -34.0}, {151.5, -34.0}, {151.5, -33.5}, {151.0, -33.5}, {151.0, -34.0}]],
          [[{115.5, -32.5}, {116.5, -32.5}, {116.5, -31.5}, {115.5, -31.5}, {115.5, -32.5}]]
        ],
        srid: 4326
      }

      sydney_search = polygon(151.2, -33.8, 152.0, -33.3)
      assert {:known, true} = StIntersects.evaluate(%{arguments: [regions, sydney_search]})
      assert {:known, true} = StIntersects.evaluate(%{arguments: [sydney_search, regions]})
    end

    test "multipolygon with no intersecting constituent does not intersect" do
      regions = %Geo.MultiPolygon{
        coordinates: [
          [[{115.5, -32.5}, {116.5, -32.5}, {116.5, -31.5}, {115.5, -31.5}, {115.5, -32.5}]],
          [[{144.9, -37.9}, {145.1, -37.9}, {145.1, -37.7}, {144.9, -37.7}, {144.9, -37.9}]]
        ],
        srid: 4326
      }

      sydney_search = polygon(151.2, -33.8, 152.0, -33.3)
      assert {:known, false} = StIntersects.evaluate(%{arguments: [regions, sydney_search]})
    end
  end

  describe "st_intersects(path, polygon) via Ash.Query" do
    test "finds places whose fibre path has a vertex inside the search polygon" do
      sydney_path = Place |> Ash.create!(%{name: "Sydney fibre", path: %Geo.LineString{
        coordinates: [{151.21, -33.87}, {151.30, -33.50}],
        srid: 4326
      }})

      melbourne_path = Place |> Ash.create!(%{name: "Melbourne fibre", path: %Geo.LineString{
        coordinates: [{144.96, -37.81}, {145.10, -37.50}],
        srid: 4326
      }})

      search = polygon(151.0, -34.0, 151.5, -33.5)

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_intersects(path, ^search))
        |> Ash.read()

      ids = Enum.map(results, & &1.id)
      assert sydney_path.id in ids
      refute melbourne_path.id in ids
    end
  end
end
