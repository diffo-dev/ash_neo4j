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
end
