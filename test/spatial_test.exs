# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.SpatialTest do
  @moduledoc """
  `AshNeo4j.Spatial.create_index/3` etc (#275) — resolves a resource +
  attribute (or nested `[attr, field]` path) to the POINT index(es)
  backing spatial pushdown.

  Pure tests assert the generated Cypher with no DB. Integration tests
  run real index DDL: in Neo4j 5 schema changes are transactional, so
  under the sandbox a created index is visible within the test's
  transaction and the rollback wipes it — no manual cleanup, no leak.
  `async: false` because index creation takes a schema lock.
  """
  use ExUnit.Case, async: false

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Cypher
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Spatial
  alias AshNeo4j.Test.Resource.Place

  setup_all do
    BoltyHelper.start()
  end

  describe "index_statements/3 — pure Cypher generation" do
    test "Point attribute → a single .point index" do
      assert {:ok, ["CREATE POINT INDEX place_location_point IF NOT EXISTS FOR (n:Place) ON (n.`location.point`)"]} =
               Spatial.index_statements(Place, :location)
    end

    test "Polygon attribute → both bbSW and bbNE companions" do
      assert {:ok, [sw, ne]} = Spatial.index_statements(Place, :bounds)

      assert sw ==
               "CREATE POINT INDEX place_bounds_bbSW IF NOT EXISTS FOR (n:Place) ON (n.`bounds.bbSW`)"

      assert ne ==
               "CREATE POINT INDEX place_bounds_bbNE IF NOT EXISTS FOR (n:Place) ON (n.`bounds.bbNE`)"
    end

    test "every non-Point geometry uses the two bbox companions" do
      for attr <- [:path, :pes, :regions] do
        assert {:ok, [sw, ne]} = Spatial.index_statements(Place, attr)
        assert sw =~ ".bbSW`)"
        assert ne =~ ".bbNE`)"
      end
    end

    test "nested geometry → dotted property; top-level attr translated, field raw" do
      assert {:ok, ["CREATE POINT INDEX place_pet_home_point IF NOT EXISTS FOR (n:Place) ON (n.`pet.home.point`)"]} =
               Spatial.index_statements(Place, [:pet, :home])
    end

    test "a one-element list path equals the bare-atom form" do
      assert Spatial.index_statements(Place, [:location]) ==
               Spatial.index_statements(Place, :location)
    end

    test ":name overrides the base; the companion suffix is still appended" do
      assert {:ok, ["CREATE POINT INDEX geo_loc_point IF NOT EXISTS FOR (n:Place) ON (n.`location.point`)"]} =
               Spatial.index_statements(Place, :location, name: "geo_loc")

      assert {:ok, [sw, ne]} = Spatial.index_statements(Place, :bounds, name: "geo_b")
      assert sw =~ "INDEX geo_b_bbSW "
      assert ne =~ "INDEX geo_b_bbNE "
    end
  end

  describe "index_statements/3 — error cases" do
    test "a non-geometry attribute is rejected" do
      assert {:error, msg} = Spatial.index_statements(Place, :name)
      assert msg =~ "not an ash_geo geometry"
    end

    test "an unknown attribute is rejected" do
      assert {:error, msg} = Spatial.index_statements(Place, :nope)
      assert msg =~ "no attribute :nope"
    end

    test "descending to a field that does not exist is rejected" do
      assert {:error, msg} = Spatial.index_statements(Place, [:pet, :nope])
      assert msg =~ ":nope"
    end

    test "descending into a non-geometry leaf field is rejected" do
      assert {:error, msg} = Spatial.index_statements(Place, [:pet, :name])
      assert msg =~ "not an ash_geo geometry"
    end

    test "a non-atom path element is rejected" do
      assert {:error, msg} = Spatial.index_statements(Place, ["location"])
      assert msg =~ "must be atoms"
    end
  end

  describe "create_index/3 + drop_index/3 — real DDL, sandbox auto-cleans" do
    setup do
      Sandbox.checkout()
      on_exit(&Sandbox.rollback/0)
    end

    test "creates a Point index, visible within the transaction" do
      assert {:ok, [%Bolty.Response{} = resp]} = Spatial.create_index(Place, :location)
      assert indexes_added(resp) == 1
      assert index_present?("place_location_point")
    end

    test "creates both corner indexes for a Polygon" do
      assert {:ok, [_sw, _ne]} = Spatial.create_index(Place, :bounds)
      assert index_present?("place_bounds_bbSW")
      assert index_present?("place_bounds_bbNE")
    end

    test "creates a nested geometry's index at the dotted path" do
      assert {:ok, [resp]} = Spatial.create_index(Place, [:pet, :home])
      assert indexes_added(resp) == 1
      assert index_present?("place_pet_home_point")
    end

    test "is idempotent — IF NOT EXISTS adds nothing the second time" do
      assert {:ok, _} = Spatial.create_index(Place, :location)
      assert {:ok, [resp]} = Spatial.create_index(Place, :location)
      assert indexes_added(resp) == 0
      assert index_present?("place_location_point")
    end

    test "recreate: true drops and rebuilds" do
      assert {:ok, _} = Spatial.create_index(Place, :location)
      assert {:ok, [resp]} = Spatial.create_index(Place, :location, recreate: true)
      assert indexes_added(resp) == 1
      assert index_present?("place_location_point")
    end

    test "drop_index removes a created index" do
      assert {:ok, _} = Spatial.create_index(Place, :location)
      assert index_present?("place_location_point")
      assert {:ok, _} = Spatial.drop_index(Place, :location)
      refute index_present?("place_location_point")
    end

    test "drop_index removes both Polygon corners" do
      assert {:ok, _} = Spatial.create_index(Place, :bounds)
      assert {:ok, _} = Spatial.drop_index(Place, :bounds)
      refute index_present?("place_bounds_bbSW")
      refute index_present?("place_bounds_bbNE")
    end
  end

  defp index_present?(name) do
    {:ok, %Bolty.Response{records: records}} = Cypher.run("SHOW INDEXES YIELD name RETURN name")
    Enum.any?(records, &(&1 == [name]))
  end

  defp indexes_added(%Bolty.Response{stats: stats}) when is_map(stats),
    do: Map.get(stats, "indexes-added", 0)

  defp indexes_added(%Bolty.Response{}), do: 0
end
