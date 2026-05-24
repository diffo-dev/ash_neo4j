# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.StWithinTest do
  @moduledoc """
  `st_within(a, b)` — true if a is contained by b. Argument-flipped `st_contains`.
  v1 evaluates in memory (no pushdown); correctness same as `st_contains`.
  """
  use ExUnit.Case, async: true

  require Ash.Query

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Functions.StWithin
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

  defp sydney_box do
    %Box{
      sw: Point.create(:wgs_84, 151.0, -34.0),
      ne: Point.create(:wgs_84, 151.5, -33.5)
    }
  end

  describe "evaluate/1 — delegates to st_contains with args flipped" do
    test "point within box" do
      inside = Point.create(:wgs_84, 151.2, -33.8)
      assert {:known, true} = StWithin.evaluate(%{arguments: [inside, sydney_box()]})
    end

    test "point outside box" do
      outside = Point.create(:wgs_84, 100.0, 0.0)
      assert {:known, false} = StWithin.evaluate(%{arguments: [outside, sydney_box()]})
    end

    test "box within box" do
      inner = %Box{
        sw: Point.create(:wgs_84, 151.1, -33.9),
        ne: Point.create(:wgs_84, 151.4, -33.6)
      }
      assert {:known, true} = StWithin.evaluate(%{arguments: [inner, sydney_box()]})
    end
  end

  describe "st_within in Ash.Query.filter (in-memory)" do
    test "finds places whose location is inside the given box" do
      sydney_place = Place |> Ash.create!(%{name: "Sydney CBD", location: Point.create(:wgs_84, 151.2093, -33.8688)})
      _outside = Place |> Ash.create!(%{name: "Perth CBD", location: Point.create(:wgs_84, 115.8617, -31.9514)})

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_within(location, ^sydney_box()))
        |> Ash.read()

      ids = Enum.map(results, & &1.id)
      assert sydney_place.id in ids
      assert length(results) == 1
    end
  end
end
