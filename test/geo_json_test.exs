# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.GeoJsonTest do
  @moduledoc """
  Tests for `AshNeo4j.GeoJson` — the RFC 7946 encode/decode wrapper
  over `:geo`. Verifies the workaround for the upstream library bug
  (always adds non-RFC `crs` member when `srid` is set) and the bbox
  derivation for every geometry shape.
  """
  use ExUnit.Case, async: true

  alias AshNeo4j.GeoJson

  describe "encode!/1 — RFC 7946 compliance" do
    test "does not include the (now-disallowed) crs member even when srid is set" do
      point = %Geo.Point{coordinates: {151.2093, -33.8688}, srid: 4326}
      json = GeoJson.encode!(point)

      refute json =~ "crs"
      refute json =~ "EPSG"
    end

    test "Point shape" do
      point = %Geo.Point{coordinates: {151.21, -33.87}, srid: 4326}
      json = GeoJson.encode!(point)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "Point"
      assert decoded["coordinates"] == [151.21, -33.87]
    end

    test "coordinates are lng-first per RFC 7946 §3.1.1" do
      sydney = %Geo.Point{coordinates: {151.2093, -33.8688}, srid: 4326}
      decoded = sydney |> GeoJson.encode!() |> Jason.decode!()

      assert [lng, lat] = decoded["coordinates"]
      assert lng == 151.2093
      assert lat == -33.8688
    end
  end

  describe "encode!/1 — bbox inclusion" do
    test "Point bbox is [lng, lat, lng, lat]" do
      point = %Geo.Point{coordinates: {151.21, -33.87}, srid: 4326}
      decoded = point |> GeoJson.encode!() |> Jason.decode!()

      assert decoded["bbox"] == [151.21, -33.87, 151.21, -33.87]
    end

    test "LineString bbox is min/max across vertices" do
      line = %Geo.LineString{
        coordinates: [{151.21, -33.87}, {151.30, -33.50}, {151.78, -32.93}],
        srid: 4326
      }
      decoded = line |> GeoJson.encode!() |> Jason.decode!()

      # [west, south, east, north]
      assert decoded["bbox"] == [151.21, -33.87, 151.78, -32.93]
    end

    test "Polygon bbox includes all rings (exterior + holes)" do
      poly = %Geo.Polygon{
        coordinates: [
          [{0.0, 0.0}, {10.0, 0.0}, {10.0, 10.0}, {0.0, 10.0}, {0.0, 0.0}],
          [{2.0, 2.0}, {2.0, 8.0}, {8.0, 8.0}, {8.0, 2.0}, {2.0, 2.0}]
        ],
        srid: 4326
      }
      decoded = poly |> GeoJson.encode!() |> Jason.decode!()

      assert decoded["bbox"] == [0.0, 0.0, 10.0, 10.0]
    end

    test "MultiPolygon bbox spans all polygons" do
      multi = %Geo.MultiPolygon{
        coordinates: [
          [[{0.0, 0.0}, {1.0, 0.0}, {1.0, 1.0}, {0.0, 1.0}, {0.0, 0.0}]],
          [[{10.0, 10.0}, {11.0, 10.0}, {11.0, 11.0}, {10.0, 11.0}, {10.0, 10.0}]]
        ],
        srid: 4326
      }
      decoded = multi |> GeoJson.encode!() |> Jason.decode!()

      assert decoded["bbox"] == [0.0, 0.0, 11.0, 11.0]
    end

    test "MultiLineString bbox spans all lines" do
      multi = %Geo.MultiLineString{
        coordinates: [
          [{0.0, 0.0}, {1.0, 1.0}],
          [{10.0, 10.0}, {11.0, 11.0}]
        ],
        srid: 4326
      }
      decoded = multi |> GeoJson.encode!() |> Jason.decode!()

      assert decoded["bbox"] == [0.0, 0.0, 11.0, 11.0]
    end
  end

  describe "decode!/1 — round-trip with srid: 4326 set" do
    for {label, geom} <- [
          {"Point", %Geo.Point{coordinates: {151.21, -33.87}, srid: 4326}},
          {"LineString",
           %Geo.LineString{
             coordinates: [{151.21, -33.87}, {151.30, -33.50}, {151.78, -32.93}],
             srid: 4326
           }},
          {"Polygon",
           %Geo.Polygon{
             coordinates: [
               [{0.0, 0.0}, {1.0, 0.0}, {1.0, 1.0}, {0.0, 1.0}, {0.0, 0.0}]
             ],
             srid: 4326
           }},
          {"Polygon-with-hole",
           %Geo.Polygon{
             coordinates: [
               [{0.0, 0.0}, {10.0, 0.0}, {10.0, 10.0}, {0.0, 10.0}, {0.0, 0.0}],
               [{2.0, 2.0}, {2.0, 8.0}, {8.0, 8.0}, {8.0, 2.0}, {2.0, 2.0}]
             ],
             srid: 4326
           }},
          {"MultiPoint",
           %Geo.MultiPoint{coordinates: [{1.0, 1.0}, {2.0, 2.0}], srid: 4326}},
          {"MultiLineString",
           %Geo.MultiLineString{
             coordinates: [[{0.0, 0.0}, {1.0, 1.0}], [{10.0, 10.0}, {11.0, 11.0}]],
             srid: 4326
           }},
          {"MultiPolygon",
           %Geo.MultiPolygon{
             coordinates: [
               [[{0.0, 0.0}, {1.0, 0.0}, {1.0, 1.0}, {0.0, 1.0}, {0.0, 0.0}]]
             ],
             srid: 4326
           }}
        ] do
      test "#{label}" do
        original = unquote(Macro.escape(geom))
        round_tripped = original |> GeoJson.encode!() |> GeoJson.decode!()

        assert round_tripped == original
      end
    end
  end

  describe "bbox/1 standalone" do
    test "single Point bbox collapses to the point itself" do
      assert GeoJson.bbox(%Geo.Point{coordinates: {5.0, 7.0}, srid: 4326}) == [5.0, 7.0, 5.0, 7.0]
    end

    test "LineString bbox" do
      line = %Geo.LineString{
        coordinates: [{0.0, 0.0}, {10.0, 5.0}, {3.0, 12.0}],
        srid: 4326
      }
      assert GeoJson.bbox(line) == [0.0, 0.0, 10.0, 12.0]
    end

    test "MultiLineString bbox walks both levels of nesting" do
      multi = %Geo.MultiLineString{
        coordinates: [[{1.0, 1.0}, {2.0, 2.0}], [{-5.0, -5.0}, {0.0, 0.0}]],
        srid: 4326
      }
      assert GeoJson.bbox(multi) == [-5.0, -5.0, 2.0, 2.0]
    end

    test "MultiPolygon bbox walks all three levels of nesting" do
      multi = %Geo.MultiPolygon{
        coordinates: [
          [[{0.0, 0.0}, {1.0, 0.0}, {1.0, 1.0}, {0.0, 1.0}, {0.0, 0.0}]],
          [[{100.0, 100.0}, {101.0, 100.0}, {101.0, 101.0}, {100.0, 101.0}, {100.0, 100.0}]]
        ],
        srid: 4326
      }
      assert GeoJson.bbox(multi) == [0.0, 0.0, 101.0, 101.0]
    end
  end
end
