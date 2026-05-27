# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.StClosestPointTest do
  @moduledoc """
  End-to-end test of `st_closest_point(collection, point)` over LineString
  and MultiPoint records. For a LineString it returns the true closest
  point on the nearest segment (#279) — possibly an interior edge point;
  for a MultiPoint it returns the nearest vertex. Returns a `%Geo.Point{}`.
  In-memory only — used via `Ash.calculate` rather than `Ash.Query.filter`
  (it returns a Point, not a boolean).
  """
  use ExUnit.Case, async: true

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Functions.StClosestPoint
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Place

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  defp geo(lng, lat), do: %Geo.Point{coordinates: {lng, lat}, srid: 4326}

  defp fibre_run do
    %Geo.LineString{
      coordinates: [{151.21, -33.87}, {151.30, -33.50}, {151.78, -32.93}],
      srid: 4326
    }
  end

  # A due-east segment, for clean perpendicular-foot / endpoint-clamp cases.
  defp due_east, do: %Geo.LineString{coordinates: [{151.0, -33.0}, {152.0, -33.0}], srid: 4326}

  describe "LineString round-trip via Ash" do
    test "create + read preserves the vertex coordinates intact" do
      created = Place |> Ash.create!(%{name: "Sydney to Newcastle", path: fibre_run()})
      reread = Place |> Ash.get!(created.id)

      assert %Geo.LineString{coordinates: coords, srid: 4326} = reread.path
      assert coords == [{151.21, -33.87}, {151.30, -33.50}, {151.78, -32.93}]
    end
  end

  describe "st_closest_point(line, point) via evaluate — closest point on segment (#279)" do
    test "returns the perpendicular foot in the segment interior, not a vertex" do
      {:known, %Geo.Point{coordinates: {lng, lat}, srid: 4326}} =
        StClosestPoint.evaluate(%{arguments: [due_east(), geo(151.5, -33.1)]})

      # Foot of the perpendicular from (151.5, -33.1) is ~(151.5, -33.0):
      # strictly between the two endpoints, sitting on the line.
      assert_in_delta lng, 151.5, 0.01
      assert_in_delta lat, -33.0, 0.001
      assert lng > 151.0 and lng < 152.0
    end

    test "the on-segment point is closer to the target than either vertex" do
      target = {151.5, -33.1}

      {:known, %Geo.Point{coordinates: foot}} =
        StClosestPoint.evaluate(%{arguments: [due_east(), geo(151.5, -33.1)]})

      foot_distance = AshNeo4j.Geo.haversine_meters(foot, target)
      assert foot_distance < AshNeo4j.Geo.haversine_meters({151.0, -33.0}, target)
      assert foot_distance < AshNeo4j.Geo.haversine_meters({152.0, -33.0}, target)
    end

    test "clamps to the nearest endpoint when the target is beyond the segment" do
      {:known, closest} = StClosestPoint.evaluate(%{arguments: [due_east(), geo(150.5, -33.0)]})

      assert %Geo.Point{coordinates: {151.0, -33.0}, srid: 4326} = closest
    end

    test "is never farther than the closest vertex (fibre run)" do
      for target <- [geo(151.22, -33.85), geo(151.80, -32.95), geo(151.29, -33.51)] do
        {:known, %Geo.Point{coordinates: foot}} =
          StClosestPoint.evaluate(%{arguments: [fibre_run(), target]})

        %Geo.Point{coordinates: t} = target
        foot_distance = AshNeo4j.Geo.haversine_meters(foot, t)

        nearest_vertex_distance =
          fibre_run().coordinates |> Enum.map(&AshNeo4j.Geo.haversine_meters(&1, t)) |> Enum.min()

        assert foot_distance <= nearest_vertex_distance
      end
    end

    test "returns nil for nil arguments" do
      target = geo(151.0, -33.0)
      assert {:known, nil} = StClosestPoint.evaluate(%{arguments: [nil, target]})
      assert {:known, nil} = StClosestPoint.evaluate(%{arguments: [fibre_run(), nil]})
    end
  end

  describe "st_closest_point(multipoint, point) via evaluate" do
    test "returns the nearest PE from a candidate set" do
      pes = %Geo.MultiPoint{
        coordinates: [{151.21, -33.87}, {151.50, -33.50}, {115.86, -31.95}],
        srid: 4326
      }

      {:known, closest} = StClosestPoint.evaluate(%{arguments: [pes, geo(151.22, -33.85)]})

      assert %Geo.Point{coordinates: {151.21, -33.87}, srid: 4326} = closest
    end
  end
end
