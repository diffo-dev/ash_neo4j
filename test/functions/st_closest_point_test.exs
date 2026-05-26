# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.StClosestPointTest do
  @moduledoc """
  End-to-end test of `st_closest_point(collection, point)` over LineString
  and MultiPoint records. Returns the closest vertex as a `%Geo.Point{}`.
  In-memory only — used via `Ash.calculate` rather than `Ash.Query.filter`
  (it returns a Point, not a boolean).
  """
  use ExUnit.Case, async: true

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Functions.StClosestPoint
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Place
  alias AshNeo4j.Type.LineString
  alias AshNeo4j.Type.MultiPoint
  # Bolty.Types.Point retained because LineString.vertices and MultiPoint.points
  # are still held internally as Bolty Points until those types migrate.
  alias Bolty.Types.Point

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  defp geo(lng, lat), do: %Geo.Point{coordinates: {lng, lat}, srid: 4326}

  defp fibre_run do
    %LineString{
      vertices: [
        Point.create(:wgs_84, 151.21, -33.87),
        Point.create(:wgs_84, 151.30, -33.50),
        Point.create(:wgs_84, 151.78, -32.93)
      ]
    }
  end

  describe "LineString round-trip via Ash" do
    test "create + read preserves the vertex array intact" do
      created = Place |> Ash.create!(%{name: "Sydney to Newcastle", path: fibre_run()})
      reread = Place |> Ash.get!(created.id)

      assert %LineString{vertices: vs} = reread.path
      assert length(vs) == 3
      assert Enum.map(vs, & &1.x) == [151.21, 151.30, 151.78]
      assert Enum.map(vs, & &1.y) == [-33.87, -33.50, -32.93]
    end
  end

  describe "st_closest_point(line, point) via evaluate" do
    test "returns the vertex nearest the target — Sydney end" do
      {:known, closest} = StClosestPoint.evaluate(%{arguments: [fibre_run(), geo(151.22, -33.85)]})

      assert %Geo.Point{coordinates: {151.21, -33.87}, srid: 4326} = closest
    end

    test "returns the vertex nearest the target — Newcastle end" do
      {:known, closest} = StClosestPoint.evaluate(%{arguments: [fibre_run(), geo(151.80, -32.95)]})

      assert %Geo.Point{coordinates: {151.78, -32.93}, srid: 4326} = closest
    end

    test "returns the middle vertex when the target is closest to it" do
      {:known, closest} = StClosestPoint.evaluate(%{arguments: [fibre_run(), geo(151.29, -33.51)]})

      assert %Geo.Point{coordinates: {151.30, -33.50}, srid: 4326} = closest
    end

    test "returns nil for nil arguments" do
      target = geo(151.0, -33.0)
      assert {:known, nil} = StClosestPoint.evaluate(%{arguments: [nil, target]})
      assert {:known, nil} = StClosestPoint.evaluate(%{arguments: [fibre_run(), nil]})
    end
  end

  describe "st_closest_point(multipoint, point) via evaluate" do
    test "returns the nearest PE from a candidate set" do
      pes = %MultiPoint{
        points: [
          Point.create(:wgs_84, 151.21, -33.87),
          Point.create(:wgs_84, 151.50, -33.50),
          Point.create(:wgs_84, 115.86, -31.95)
        ]
      }

      {:known, closest} = StClosestPoint.evaluate(%{arguments: [pes, geo(151.22, -33.85)]})

      assert %Geo.Point{coordinates: {151.21, -33.87}, srid: 4326} = closest
    end
  end
end
