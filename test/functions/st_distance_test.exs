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
  alias AshNeo4j.Type.LineString
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

  describe "evaluate/1 — LineString to point (closest-vertex approximation)" do
    setup do
      line = %LineString{
        vertices: [
          Point.create(:wgs_84, 151.21, -33.87),
          Point.create(:wgs_84, 151.30, -33.50),
          Point.create(:wgs_84, 151.78, -32.93)
        ]
      }

      {:ok, fibre: line}
    end

    test "returns the haversine distance to the nearest vertex", %{fibre: line} do
      sydney_target = Point.create(:wgs_84, 151.22, -33.85)
      {:known, meters} = StDistance.evaluate(%{arguments: [line, sydney_target]})

      # Nearest vertex is (151.21, -33.87); within a few km of the target.
      assert meters < 5_000
    end

    test "is symmetric in arguments", %{fibre: line} do
      target = Point.create(:wgs_84, 151.80, -32.95)
      {:known, ab} = StDistance.evaluate(%{arguments: [line, target]})
      {:known, ba} = StDistance.evaluate(%{arguments: [target, line]})

      assert ab == ba
    end
  end

  describe "st_dwithin LineString filter via Ash.Query" do
    setup do
      near = Place |> Ash.create!(%{name: "Near fibre", path: %LineString{
        vertices: [
          Point.create(:wgs_84, 151.21, -33.87),
          Point.create(:wgs_84, 151.30, -33.50)
        ]
      }})

      far = Place |> Ash.create!(%{name: "Far fibre", path: %LineString{
        vertices: [
          Point.create(:wgs_84, 144.96, -37.81),
          Point.create(:wgs_84, 145.10, -37.50)
        ]
      }})

      {:ok, near: near, far: far}
    end

    test "matches paths whose closest vertex is within the threshold", %{near: near, far: far} do
      customer = Point.create(:wgs_84, 151.22, -33.85)
      threshold = 50_000.0

      # Sanity: unfiltered read returns both paths
      {:ok, all} = Place |> Ash.read()
      assert near.id in Enum.map(all, & &1.id)
      assert far.id in Enum.map(all, & &1.id)

      # Sanity: re-read near and confirm path round-trips as a LineString struct
      reread = Place |> Ash.get!(near.id)
      assert %LineString{vertices: vs} = reread.path
      assert length(vs) == 2

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_dwithin(path, ^customer, ^threshold))
        |> Ash.read()

      ids = Enum.map(results, & &1.id)
      assert near.id in ids
      refute far.id in ids
    end
  end
end
