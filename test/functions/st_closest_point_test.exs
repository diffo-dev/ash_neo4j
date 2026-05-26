# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.StClosestPointTest do
  @moduledoc """
  End-to-end test of `st_closest_point(collection, point)` over LineString
  records. Returns the closest vertex (a `%Bolty.Types.Point{}`) from the
  collection to the target. In-memory only — used via `Ash.calculate`
  rather than `Ash.Query.filter` (it returns a Point, not a boolean).
  """
  use ExUnit.Case, async: true

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Functions.StClosestPoint
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Place
  alias AshNeo4j.Type.LineString
  alias Bolty.Types.Point

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

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
      near_sydney = Point.create(:wgs_84, 151.22, -33.85)
      {:known, closest} = StClosestPoint.evaluate(%{arguments: [fibre_run(), near_sydney]})

      assert %Point{} = closest
      assert closest.x == 151.21
      assert closest.y == -33.87
    end

    test "returns the vertex nearest the target — Newcastle end" do
      near_newcastle = Point.create(:wgs_84, 151.80, -32.95)
      {:known, closest} = StClosestPoint.evaluate(%{arguments: [fibre_run(), near_newcastle]})

      assert closest.x == 151.78
      assert closest.y == -32.93
    end

    test "returns the middle vertex when the target is closest to it" do
      near_middle = Point.create(:wgs_84, 151.29, -33.51)
      {:known, closest} = StClosestPoint.evaluate(%{arguments: [fibre_run(), near_middle]})

      assert closest.x == 151.30
      assert closest.y == -33.50
    end

    test "returns nil for nil arguments" do
      target = Point.create(:wgs_84, 151.0, -33.0)
      assert {:known, nil} = StClosestPoint.evaluate(%{arguments: [nil, target]})
      assert {:known, nil} = StClosestPoint.evaluate(%{arguments: [fibre_run(), nil]})
    end
  end
end
