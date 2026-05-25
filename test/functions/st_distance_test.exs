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
  alias Bolty.Types.Point

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  describe "evaluate/1 — haversine on WGS-84 points" do
    test "Sydney to Melbourne is ~713 km within haversine precision" do
      sydney = Point.create(:wgs_84, 151.2093, -33.8688)
      melbourne = Point.create(:wgs_84, 144.9631, -37.8136)

      {:known, meters} = StDistance.evaluate(%{arguments: [sydney, melbourne]})

      assert_in_delta meters, 713_000, 5_000
    end

    test "same point is 0" do
      sydney = Point.create(:wgs_84, 151.2093, -33.8688)

      {:known, meters} = StDistance.evaluate(%{arguments: [sydney, sydney]})
      assert meters == 0.0
    end

    test "nil argument yields nil" do
      sydney = Point.create(:wgs_84, 151.2093, -33.8688)
      assert {:known, nil} = StDistance.evaluate(%{arguments: [nil, sydney]})
      assert {:known, nil} = StDistance.evaluate(%{arguments: [sydney, nil]})
    end
  end

  describe "st_distance in Ash.Query.filter" do
    setup do
      sydney = Place |> Ash.create!(%{name: "Sydney CBD", location: Point.create(:wgs_84, 151.2093, -33.8688)})
      melbourne = Place |> Ash.create!(%{name: "Melbourne CBD", location: Point.create(:wgs_84, 144.9631, -37.8136)})
      {:ok, sydney: sydney, melbourne: melbourne}
    end

    test "finds places within a given distance of a reference point", %{sydney: sydney, melbourne: melbourne} do
      near_sydney = Point.create(:wgs_84, 151.2, -33.85)
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
      near_sydney = Point.create(:wgs_84, 151.2, -33.85)
      threshold = 100.0

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_distance(location, ^near_sydney) < ^threshold)
        |> Ash.read()

      assert results == []
    end
  end
end
