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

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  defp geo(lng, lat), do: %Geo.Point{coordinates: {lng, lat}, srid: 4326}

  defp sydney_polygon do
    %Geo.Polygon{
      coordinates: [
        [{151.0, -34.0}, {151.5, -34.0}, {151.5, -33.5}, {151.0, -33.5}, {151.0, -34.0}]
      ],
      srid: 4326
    }
  end

  describe "evaluate/1 — delegates to st_contains with args flipped" do
    test "point within polygon" do
      assert {:known, true} = StWithin.evaluate(%{arguments: [geo(151.2, -33.8), sydney_polygon()]})
    end

    test "point outside polygon" do
      assert {:known, false} = StWithin.evaluate(%{arguments: [geo(100.0, 0.0), sydney_polygon()]})
    end

    test "polygon within polygon" do
      inner = %Geo.Polygon{
        coordinates: [
          [{151.1, -33.9}, {151.4, -33.9}, {151.4, -33.6}, {151.1, -33.6}, {151.1, -33.9}]
        ],
        srid: 4326
      }
      assert {:known, true} = StWithin.evaluate(%{arguments: [inner, sydney_polygon()]})
    end
  end

  describe "st_within in Ash.Query.filter (in-memory)" do
    test "finds places whose location is inside the given polygon" do
      sydney_place = Place |> Ash.create!(%{name: "Sydney CBD", location: geo(151.2093, -33.8688)})
      _outside = Place |> Ash.create!(%{name: "Perth CBD", location: geo(115.8617, -31.9514)})

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_within(location, ^sydney_polygon()))
        |> Ash.read()

      ids = Enum.map(results, & &1.id)
      assert sydney_place.id in ids
      assert length(results) == 1
    end
  end
end
