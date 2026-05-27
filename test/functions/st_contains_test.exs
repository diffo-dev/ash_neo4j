# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.StContainsTest do
  @moduledoc """
  End-to-end test of `st_contains(polygon, point)` as an Ash query
  expression, with pushdown to Neo4j's native `point.withinBBox` via the
  `<attr>.bbSW`/`<attr>.bbNE` scalar companions.
  """
  use ExUnit.Case, async: true

  require Ash.Query

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Functions.StContains
  alias AshNeo4j.Test.Resource.Place

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  defp geo(lng, lat), do: %Geo.Point{coordinates: {lng, lat}, srid: 4326}

  defp polygon(sw_x, sw_y, ne_x, ne_y) do
    %Geo.Polygon{
      coordinates: [
        [{sw_x, sw_y}, {ne_x, sw_y}, {ne_x, ne_y}, {sw_x, ne_y}, {sw_x, sw_y}]
      ],
      srid: 4326
    }
  end

  defp sydney_polygon, do: polygon(151.0, -34.0, 151.5, -33.5)

  describe "st_contains in Ash.Query.filter" do
    setup do
      sydney = Place |> Ash.create!(%{name: "Sydney bbox", bounds: sydney_polygon()})
      perth = Place |> Ash.create!(%{name: "Perth bbox", bounds: polygon(115.5, -32.5, 116.5, -31.5)})

      {:ok, sydney: sydney, perth: perth}
    end

    test "returns places whose bounds contain the test point", %{sydney: sydney} do
      inside_sydney = geo(151.2, -33.8)

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_contains(bounds, ^inside_sydney))
        |> Ash.read()

      ids = Enum.map(results, & &1.id)
      assert sydney.id in ids
    end

    test "excludes places whose bounds do not contain the test point", %{sydney: sydney, perth: perth} do
      inside_sydney = geo(151.2, -33.8)

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_contains(bounds, ^inside_sydney))
        |> Ash.read()

      ids = Enum.map(results, & &1.id)
      assert sydney.id in ids
      refute perth.id in ids
    end

    test "returns no results when the test point is outside all polygons" do
      middle_of_australia = geo(134.0, -25.0)

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_contains(bounds, ^middle_of_australia))
        |> Ash.read()

      assert results == []
    end
  end

  describe "st_contains polygon-polygon (pushed down as 2 ANDed point.withinBBox)" do
    setup do
      sydney = Place |> Ash.create!(%{name: "Sydney bbox", bounds: sydney_polygon()})
      {:ok, sydney: sydney}
    end

    test "matches when the inner polygon is fully inside the place's bounds", %{sydney: sydney} do
      inner = polygon(151.1, -33.9, 151.4, -33.6)

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_contains(bounds, ^inner))
        |> Ash.read()

      ids = Enum.map(results, & &1.id)
      assert sydney.id in ids
    end

    test "matches when the inner polygon equals the place's bounds (inclusive)", %{sydney: sydney} do
      same = sydney_polygon()

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_contains(bounds, ^same))
        |> Ash.read()

      ids = Enum.map(results, & &1.id)
      assert sydney.id in ids
    end

    test "rejects when the inner polygon extends beyond the place's bounds" do
      bigger = polygon(150.0, -34.5, 152.0, -33.0)

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_contains(bounds, ^bigger))
        |> Ash.read()

      assert results == []
    end

    test "rejects when the inner polygon partially overlaps the place's bounds" do
      overlap = polygon(151.3, -33.8, 151.7, -33.4)

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_contains(bounds, ^overlap))
        |> Ash.read()

      assert results == []
    end
  end

  describe "st_contains(polygon, multipoint) — all-of semantics" do
    test "true when every point of the MultiPoint is inside the Polygon's bbox" do
      inside_sydney = %Geo.MultiPoint{
        coordinates: [{151.10, -33.80}, {151.40, -33.60}],
        srid: 4326
      }

      assert {:known, true} = StContains.evaluate(%{arguments: [sydney_polygon(), inside_sydney]})
    end

    test "false when any point of the MultiPoint is outside the Polygon" do
      mixed = %Geo.MultiPoint{
        coordinates: [{151.10, -33.80}, {115.86, -31.95}],
        srid: 4326
      }

      assert {:known, false} = StContains.evaluate(%{arguments: [sydney_polygon(), mixed]})
    end
  end

  describe "st_contains(multipolygon, point) — any-of semantics" do
    setup do
      service_area = %Geo.MultiPolygon{
        coordinates: [
          [[{151.0, -34.0}, {151.5, -34.0}, {151.5, -33.5}, {151.0, -33.5}, {151.0, -34.0}]],
          [[{151.6, -33.4}, {152.0, -33.4}, {152.0, -33.0}, {151.6, -33.0}, {151.6, -33.4}]]
        ],
        srid: 4326
      }

      {:ok, service_area: service_area}
    end

    test "true when the point falls in any constituent polygon", %{service_area: sa} do
      assert {:known, true} = StContains.evaluate(%{arguments: [sa, geo(151.2, -33.8)]})
      assert {:known, true} = StContains.evaluate(%{arguments: [sa, geo(151.8, -33.2)]})
    end

    test "false when the point falls in none of the polygons", %{service_area: sa} do
      assert {:known, false} = StContains.evaluate(%{arguments: [sa, geo(151.55, -33.45)]})
    end

    test "round-trips through Ash storage and pushes through in-memory filter", %{service_area: sa} do
      created = Place |> Ash.create!(%{name: "SA covering Sydney", regions: sa})
      reread = Place |> Ash.get!(created.id)

      assert %Geo.MultiPolygon{coordinates: [_, _]} = reread.regions

      in_first = geo(151.2, -33.8)

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_contains(regions, ^in_first))
        |> Ash.read()

      assert created.id in Enum.map(results, & &1.id)
    end
  end
end
