# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.StIntersectsTest do
  @moduledoc """
  `st_intersects(box, box)` — true if the two boxes share any space.
  v1 evaluates in memory.
  """
  use ExUnit.Case, async: true

  require Ash.Query

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Functions.StIntersects
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Place
  alias AshNeo4j.Type.Box
  alias AshNeo4j.Type.LineString
  alias AshNeo4j.Type.MultiBox
  alias AshNeo4j.Type.MultiPoint
  alias Bolty.Types.Point

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  defp box(sw_x, sw_y, ne_x, ne_y) do
    %Box{
      sw: Point.create(:wgs_84, sw_x, sw_y),
      ne: Point.create(:wgs_84, ne_x, ne_y)
    }
  end

  describe "evaluate/1" do
    test "fully overlapping boxes intersect" do
      a = box(0.0, 0.0, 10.0, 10.0)
      b = box(2.0, 2.0, 8.0, 8.0)
      assert {:known, true} = StIntersects.evaluate(%{arguments: [a, b]})
    end

    test "partially overlapping boxes intersect" do
      a = box(0.0, 0.0, 5.0, 5.0)
      b = box(3.0, 3.0, 8.0, 8.0)
      assert {:known, true} = StIntersects.evaluate(%{arguments: [a, b]})
    end

    test "edge-touching boxes intersect (inclusive boundary)" do
      a = box(0.0, 0.0, 5.0, 5.0)
      b = box(5.0, 0.0, 10.0, 5.0)
      assert {:known, true} = StIntersects.evaluate(%{arguments: [a, b]})
    end

    test "disjoint boxes do not intersect" do
      a = box(0.0, 0.0, 5.0, 5.0)
      b = box(10.0, 10.0, 15.0, 15.0)
      assert {:known, false} = StIntersects.evaluate(%{arguments: [a, b]})
    end

    test "nil arguments yield false" do
      a = box(0.0, 0.0, 5.0, 5.0)
      assert {:known, false} = StIntersects.evaluate(%{arguments: [nil, a]})
      assert {:known, false} = StIntersects.evaluate(%{arguments: [a, nil]})
    end
  end

  describe "st_intersects in Ash.Query.filter (in-memory)" do
    test "finds places whose bounds intersect the given box" do
      sydney = Place |> Ash.create!(%{name: "Sydney", bounds: box(151.0, -34.0, 151.5, -33.5)})
      _perth = Place |> Ash.create!(%{name: "Perth", bounds: box(115.5, -32.5, 116.5, -31.5)})

      overlap_with_sydney = box(151.2, -33.8, 152.0, -33.3)

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_intersects(bounds, ^overlap_with_sydney))
        |> Ash.read()

      ids = Enum.map(results, & &1.id)
      assert sydney.id in ids
      assert length(results) == 1
    end
  end

  describe "evaluate/1 — LineString vs Box (vertex-in-box approximation)" do
    test "line with a vertex inside the box intersects" do
      line = %LineString{vertices: [
        Point.create(:wgs_84, 151.21, -33.87),
        Point.create(:wgs_84, 151.30, -33.50),
        Point.create(:wgs_84, 151.78, -32.93)
      ]}

      sydney_bbox = box(151.0, -34.0, 151.5, -33.5)
      assert {:known, true} = StIntersects.evaluate(%{arguments: [line, sydney_bbox]})
      assert {:known, true} = StIntersects.evaluate(%{arguments: [sydney_bbox, line]})
    end

    test "line with no vertex inside the box does not intersect (v1 limitation: segment-crossing is missed)" do
      # Line skirts past the box without any vertex landing inside it.
      line = %LineString{vertices: [
        Point.create(:wgs_84, 150.0, -34.0),
        Point.create(:wgs_84, 152.0, -34.0)
      ]}

      # Sit the box completely above where the line runs.
      far_box = box(151.0, -33.0, 151.5, -32.5)
      assert {:known, false} = StIntersects.evaluate(%{arguments: [line, far_box]})
    end
  end

  describe "evaluate/1 — MultiPoint vs Box (any-of, exact)" do
    test "multipoint with a point inside the box intersects" do
      pes = %MultiPoint{points: [
        Point.create(:wgs_84, 151.21, -33.87),
        Point.create(:wgs_84, 115.86, -31.95)
      ]}

      sydney_bbox = box(151.0, -34.0, 151.5, -33.5)
      assert {:known, true} = StIntersects.evaluate(%{arguments: [pes, sydney_bbox]})
      assert {:known, true} = StIntersects.evaluate(%{arguments: [sydney_bbox, pes]})
    end

    test "multipoint with no point inside the box does not intersect" do
      pes = %MultiPoint{points: [
        Point.create(:wgs_84, 115.86, -31.95),
        Point.create(:wgs_84, 144.96, -37.81)
      ]}

      sydney_bbox = box(151.0, -34.0, 151.5, -33.5)
      assert {:known, false} = StIntersects.evaluate(%{arguments: [pes, sydney_bbox]})
    end
  end

  describe "evaluate/1 — MultiBox vs Box (any-of)" do
    test "multibox with any constituent intersecting the box intersects" do
      regions = %MultiBox{boxes: [
        box(151.0, -34.0, 151.5, -33.5),
        box(115.5, -32.5, 116.5, -31.5)
      ]}

      sydney_search = box(151.2, -33.8, 152.0, -33.3)
      assert {:known, true} = StIntersects.evaluate(%{arguments: [regions, sydney_search]})
      assert {:known, true} = StIntersects.evaluate(%{arguments: [sydney_search, regions]})
    end

    test "multibox with no intersecting constituent does not intersect" do
      regions = %MultiBox{boxes: [
        box(115.5, -32.5, 116.5, -31.5),
        box(144.9, -37.9, 145.1, -37.7)
      ]}

      sydney_search = box(151.2, -33.8, 152.0, -33.3)
      assert {:known, false} = StIntersects.evaluate(%{arguments: [regions, sydney_search]})
    end
  end

  describe "st_intersects(path, box) via Ash.Query" do
    test "finds places whose fibre path has a vertex inside the search box" do
      sydney_path = Place |> Ash.create!(%{name: "Sydney fibre", path: %LineString{
        vertices: [
          Point.create(:wgs_84, 151.21, -33.87),
          Point.create(:wgs_84, 151.30, -33.50)
        ]
      }})

      melbourne_path = Place |> Ash.create!(%{name: "Melbourne fibre", path: %LineString{
        vertices: [
          Point.create(:wgs_84, 144.96, -37.81),
          Point.create(:wgs_84, 145.10, -37.50)
        ]
      }})

      search = box(151.0, -34.0, 151.5, -33.5)

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
