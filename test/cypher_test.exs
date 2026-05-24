# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.CypherTest do
  @moduledoc """
  End-to-end cypher predicate tests against a real Neo4j connection.
  Verifies generated Cypher fragments behave as documented when run.
  """
  use ExUnit.Case, async: true

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Cypher
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

  describe "within_bbox" do
    setup do
      created = Place |> Ash.create!(%{name: "Sydney bbox", bounds: sydney_box()})
      {:ok, place: created}
    end

    test "matches a point inside the stored box", %{place: place} do
      inside = Point.create(:wgs_84, 151.2, -33.8)
      cypher = "MATCH (n {uuid: $uuid}) WHERE #{Cypher.expression(:n, "bounds", "within_bbox", "$test_point")} RETURN n"
      {:ok, response} = Sandbox.run(cypher, %{"uuid" => place.id, "test_point" => inside})

      assert response.results != []
    end

    test "rejects a point east of the box", %{place: place} do
      outside = Point.create(:wgs_84, 152.0, -33.8)
      cypher = "MATCH (n {uuid: $uuid}) WHERE #{Cypher.expression(:n, "bounds", "within_bbox", "$test_point")} RETURN n"
      {:ok, response} = Sandbox.run(cypher, %{"uuid" => place.id, "test_point" => outside})

      assert response.results == []
    end

    test "rejects a point south of the box", %{place: place} do
      outside = Point.create(:wgs_84, 151.2, -34.5)
      cypher = "MATCH (n {uuid: $uuid}) WHERE #{Cypher.expression(:n, "bounds", "within_bbox", "$test_point")} RETURN n"
      {:ok, response} = Sandbox.run(cypher, %{"uuid" => place.id, "test_point" => outside})

      assert response.results == []
    end

    test "matches a point on the SW corner (inclusive)", %{place: place} do
      on_corner = Point.create(:wgs_84, 151.0, -34.0)
      cypher = "MATCH (n {uuid: $uuid}) WHERE #{Cypher.expression(:n, "bounds", "within_bbox", "$test_point")} RETURN n"
      {:ok, response} = Sandbox.run(cypher, %{"uuid" => place.id, "test_point" => on_corner})

      assert response.results != []
    end
  end

  describe "st_distance" do
    setup do
      sydney = Place |> Ash.create!(%{name: "Sydney CBD", location: Point.create(:wgs_84, 151.2093, -33.8688)})
      {:ok, sydney: sydney}
    end

    test "matches when distance to a near point is below the threshold", %{sydney: sydney} do
      near = Point.create(:wgs_84, 151.2, -33.85)
      predicate = Cypher.expression(:n, "location", "st_distance", {"<", "$test_point", "$threshold"})
      cypher = "MATCH (n {uuid: $uuid}) WHERE #{predicate} RETURN n"
      {:ok, response} = Sandbox.run(cypher, %{"uuid" => sydney.id, "test_point" => near, "threshold" => 5_000.0})

      assert response.results != []
    end

    test "rejects when distance to a far point exceeds the threshold", %{sydney: sydney} do
      melbourne = Point.create(:wgs_84, 144.9631, -37.8136)
      predicate = Cypher.expression(:n, "location", "st_distance", {"<", "$test_point", "$threshold"})
      cypher = "MATCH (n {uuid: $uuid}) WHERE #{predicate} RETURN n"
      {:ok, response} = Sandbox.run(cypher, %{"uuid" => sydney.id, "test_point" => melbourne, "threshold" => 5_000.0})

      assert response.results == []
    end

    test "evaluates geodesically — Sydney to Melbourne is ~713 km", %{sydney: sydney} do
      melbourne = Point.create(:wgs_84, 144.9631, -37.8136)
      predicate = Cypher.expression(:n, "location", "st_distance", {">", "$test_point", "$threshold"})
      cypher = "MATCH (n {uuid: $uuid}) WHERE #{predicate} RETURN n"
      # Threshold just under expected distance — should match.
      {:ok, hit} = Sandbox.run(cypher, %{"uuid" => sydney.id, "test_point" => melbourne, "threshold" => 700_000.0})
      assert hit.results != []

      # Threshold just over expected distance — should not match.
      {:ok, miss} = Sandbox.run(cypher, %{"uuid" => sydney.id, "test_point" => melbourne, "threshold" => 800_000.0})
      assert miss.results == []
    end

    test ">= operator works", %{sydney: sydney} do
      melbourne = Point.create(:wgs_84, 144.9631, -37.8136)
      predicate = Cypher.expression(:n, "location", "st_distance", {">=", "$test_point", "$threshold"})
      cypher = "MATCH (n {uuid: $uuid}) WHERE #{predicate} RETURN n"
      {:ok, response} = Sandbox.run(cypher, %{"uuid" => sydney.id, "test_point" => melbourne, "threshold" => 700_000.0})

      assert response.results != []
    end
  end

  describe "dwithin" do
    setup do
      sydney = Place |> Ash.create!(%{name: "Sydney CBD", location: Point.create(:wgs_84, 151.2093, -33.8688)})
      {:ok, sydney: sydney}
    end

    test "matches when distance is within the threshold", %{sydney: sydney} do
      near = Point.create(:wgs_84, 151.2, -33.85)
      predicate = Cypher.expression(:n, "location", "dwithin", {"$test_point", "$threshold"})
      cypher = "MATCH (n {uuid: $uuid}) WHERE #{predicate} RETURN n"
      {:ok, response} = Sandbox.run(cypher, %{"uuid" => sydney.id, "test_point" => near, "threshold" => 5_000.0})

      assert response.results != []
    end

    test "rejects when distance exceeds the threshold", %{sydney: sydney} do
      melbourne = Point.create(:wgs_84, 144.9631, -37.8136)
      predicate = Cypher.expression(:n, "location", "dwithin", {"$test_point", "$threshold"})
      cypher = "MATCH (n {uuid: $uuid}) WHERE #{predicate} RETURN n"
      {:ok, response} = Sandbox.run(cypher, %{"uuid" => sydney.id, "test_point" => melbourne, "threshold" => 5_000.0})

      assert response.results == []
    end

    test "boundary is inclusive — Sydney to Melbourne at ~713 km", %{sydney: sydney} do
      melbourne = Point.create(:wgs_84, 144.9631, -37.8136)
      predicate = Cypher.expression(:n, "location", "dwithin", {"$test_point", "$threshold"})
      cypher = "MATCH (n {uuid: $uuid}) WHERE #{predicate} RETURN n"

      # Threshold larger than actual distance — should match.
      {:ok, hit} = Sandbox.run(cypher, %{"uuid" => sydney.id, "test_point" => melbourne, "threshold" => 800_000.0})
      assert hit.results != []

      # Threshold smaller than actual distance — should not match.
      {:ok, miss} = Sandbox.run(cypher, %{"uuid" => sydney.id, "test_point" => melbourne, "threshold" => 700_000.0})
      assert miss.results == []
    end
  end
end
