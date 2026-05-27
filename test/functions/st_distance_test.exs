# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.StDistanceTest do
  @moduledoc """
  Tests for `st_distance(point, point)` — the function itself (haversine)
  and filter usage (`st_distance(loc, ^p) <op> ^km`).
  """
  use ExUnit.Case, async: true

  require Ash.Query

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Functions.StDistance
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Place

  defp geo(lng, lat), do: %Geo.Point{coordinates: {lng, lat}, srid: 4326}

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  describe "evaluate/1 — haversine on WGS-84 points" do
    test "Sydney to Melbourne is ~713 km within haversine precision" do
      {:known, meters} = StDistance.evaluate(%{arguments: [geo(151.2093, -33.8688), geo(144.9631, -37.8136)]})

      assert_in_delta meters, 713_000, 5_000
    end

    test "same point is 0" do
      sydney = geo(151.2093, -33.8688)

      {:known, meters} = StDistance.evaluate(%{arguments: [sydney, sydney]})
      assert meters == 0.0
    end

    test "nil argument yields nil" do
      sydney = geo(151.2093, -33.8688)
      assert {:known, nil} = StDistance.evaluate(%{arguments: [nil, sydney]})
      assert {:known, nil} = StDistance.evaluate(%{arguments: [sydney, nil]})
    end
  end

  describe "st_distance in Ash.Query.filter" do
    setup do
      sydney = Place |> Ash.create!(%{name: "Sydney CBD", location: geo(151.2093, -33.8688)})
      melbourne = Place |> Ash.create!(%{name: "Melbourne CBD", location: geo(144.9631, -37.8136)})
      {:ok, sydney: sydney, melbourne: melbourne}
    end

    test "finds places within a given distance of a reference point", %{sydney: sydney, melbourne: melbourne} do
      near_sydney = geo(151.2, -33.85)
      threshold = 50_000.0

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_distance(location, ^near_sydney) < ^threshold)
        |> Ash.read()

      ids = Enum.map(results, & &1.id)
      assert sydney.id in ids
      refute melbourne.id in ids
    end

    test "returns nothing when threshold is below all distances" do
      near_sydney = geo(151.2, -33.85)
      threshold = 100.0

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_distance(location, ^near_sydney) < ^threshold)
        |> Ash.read()

      assert results == []
    end
  end

  describe "evaluate/1 — LineString to point (closest point on segment, #279)" do
    setup do
      line = %Geo.LineString{
        coordinates: [{151.21, -33.87}, {151.30, -33.50}, {151.78, -32.93}],
        srid: 4326
      }

      {:ok, fibre: line}
    end

    test "measures to the nearest point on a segment", %{fibre: line} do
      {:known, meters} = StDistance.evaluate(%{arguments: [line, geo(151.22, -33.85)]})

      assert meters < 5_000
    end

    test "is symmetric in arguments", %{fibre: line} do
      target = geo(151.80, -32.95)
      {:known, ab} = StDistance.evaluate(%{arguments: [line, target]})
      {:known, ba} = StDistance.evaluate(%{arguments: [target, line]})

      assert ab == ba
    end

    test "closest-point-on-segment is shorter than closest-vertex for a mid-edge target" do
      # A single long due-east segment; the target sits perpendicular to its
      # midpoint, far from either endpoint. The old closest-vertex answer
      # overstated this badly; closest-point-on-segment reads the real
      # perpendicular distance.
      segment = %Geo.LineString{coordinates: [{151.0, -33.0}, {152.0, -33.0}], srid: 4326}
      target = geo(151.5, -33.1)

      {:known, on_segment} = StDistance.evaluate(%{arguments: [segment, target]})

      nearest_vertex =
        [{151.0, -33.0}, {152.0, -33.0}]
        |> Enum.map(&AshNeo4j.Geo.haversine_meters(&1, {151.5, -33.1}))
        |> Enum.min()

      # ~0.1° of latitude ≈ 11 km perpendicular; the nearest vertex is ~47 km.
      assert_in_delta on_segment, 11_100, 200
      assert on_segment < nearest_vertex / 3
    end
  end

  describe "evaluate/1 — point to Polygon (#279)" do
    # Unit square with a square hole punched in the middle.
    defp holed do
      %Geo.Polygon{
        coordinates: [
          [{0.0, 0.0}, {10.0, 0.0}, {10.0, 10.0}, {0.0, 10.0}, {0.0, 0.0}],
          [{3.0, 3.0}, {7.0, 3.0}, {7.0, 7.0}, {3.0, 7.0}, {3.0, 3.0}]
        ],
        srid: 4326
      }
    end

    test "is 0 when the point is inside the polygon (solid part)" do
      assert {:known, +0.0} = StDistance.evaluate(%{arguments: [holed(), geo(1.0, 1.0)]})
    end

    test "is the distance to the nearest exterior edge when the point is outside" do
      # 1° west of the exterior's west edge, at the equator-ish band.
      {:known, meters} = StDistance.evaluate(%{arguments: [holed(), geo(-1.0, 5.0)]})
      assert_in_delta meters, AshNeo4j.Geo.haversine_meters({-1.0, 5.0}, {0.0, 5.0}), 1.0
    end

    test "is the distance to the hole's ring when the point sits in a hole" do
      # (5,5) is the hole centre — outside the polygon; nearest boundary is
      # the hole ring 2° away (to the edge at x=3 or x=7).
      {:known, meters} = StDistance.evaluate(%{arguments: [holed(), geo(5.0, 5.0)]})
      assert_in_delta meters, AshNeo4j.Geo.haversine_meters({5.0, 5.0}, {3.0, 5.0}), 1.0
    end

    test "is symmetric in arguments" do
      {:known, ab} = StDistance.evaluate(%{arguments: [holed(), geo(-1.0, 5.0)]})
      {:known, ba} = StDistance.evaluate(%{arguments: [geo(-1.0, 5.0), holed()]})
      assert ab == ba
    end
  end

  describe "evaluate/1 — point to MultiPolygon / MultiLineString (#279)" do
    test "MultiPolygon is 0 inside any constituent, else nearest boundary" do
      mp = %Geo.MultiPolygon{
        coordinates: [
          [[{0.0, 0.0}, {1.0, 0.0}, {1.0, 1.0}, {0.0, 1.0}, {0.0, 0.0}]],
          [[{10.0, 10.0}, {11.0, 10.0}, {11.0, 11.0}, {10.0, 11.0}, {10.0, 10.0}]]
        ],
        srid: 4326
      }

      assert {:known, +0.0} = StDistance.evaluate(%{arguments: [mp, geo(0.5, 0.5)]})
      assert {:known, +0.0} = StDistance.evaluate(%{arguments: [mp, geo(10.5, 10.5)]})

      {:known, meters} = StDistance.evaluate(%{arguments: [mp, geo(2.0, 0.5)]})
      assert_in_delta meters, AshNeo4j.Geo.haversine_meters({2.0, 0.5}, {1.0, 0.5}), 1.0
    end

    test "MultiLineString measures to the nearest segment of any constituent line" do
      mls = %Geo.MultiLineString{
        coordinates: [
          [{151.0, -33.0}, {152.0, -33.0}],
          [{144.0, -37.0}, {145.0, -37.0}]
        ],
        srid: 4326
      }

      {:known, meters} = StDistance.evaluate(%{arguments: [mls, geo(151.5, -33.1)]})
      assert_in_delta meters, 11_100, 200
    end
  end

  describe "st_dwithin LineString filter via Ash.Query" do
    setup do
      near =
        Place
        |> Ash.create!(%{
          name: "Near fibre",
          path: %Geo.LineString{
            coordinates: [{151.21, -33.87}, {151.30, -33.50}],
            srid: 4326
          }
        })

      far =
        Place
        |> Ash.create!(%{
          name: "Far fibre",
          path: %Geo.LineString{
            coordinates: [{144.96, -37.81}, {145.10, -37.50}],
            srid: 4326
          }
        })

      {:ok, near: near, far: far}
    end

    test "matches paths whose closest vertex is within the threshold", %{near: near, far: far} do
      customer = geo(151.22, -33.85)
      threshold = 50_000.0

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_dwithin(path, ^customer, ^threshold))
        |> Ash.read()

      ids = Enum.map(results, & &1.id)
      assert near.id in ids
      refute far.id in ids
    end
  end

  describe "evaluate/1 — MultiPoint to point (closest of the set, exact)" do
    test "returns the distance to the nearest point in the set" do
      pes = %Geo.MultiPoint{coordinates: [{151.21, -33.87}, {115.86, -31.95}], srid: 4326}

      {:known, meters} = StDistance.evaluate(%{arguments: [pes, geo(151.22, -33.85)]})

      # Sydney candidate is within a few km of the target.
      assert meters < 5_000
    end
  end

  describe "st_dwithin MultiPoint filter via Ash.Query" do
    test "finds places whose candidate PE set has a point within the threshold" do
      sydney =
        Place
        |> Ash.create!(%{
          name: "Sydney candidates",
          pes: %Geo.MultiPoint{
            coordinates: [{151.21, -33.87}, {151.30, -33.85}],
            srid: 4326
          }
        })

      perth =
        Place
        |> Ash.create!(%{
          name: "Perth candidates",
          pes: %Geo.MultiPoint{
            coordinates: [{115.86, -31.95}, {115.90, -32.00}],
            srid: 4326
          }
        })

      customer = geo(151.22, -33.85)
      threshold = 50_000.0

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_dwithin(pes, ^customer, ^threshold))
        |> Ash.read()

      ids = Enum.map(results, & &1.id)
      assert sydney.id in ids
      refute perth.id in ids
    end
  end
end
