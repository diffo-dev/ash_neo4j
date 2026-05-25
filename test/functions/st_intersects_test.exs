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
end
