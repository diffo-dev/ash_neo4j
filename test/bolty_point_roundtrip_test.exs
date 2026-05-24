# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.BoltyPointRoundtripTest do
  @moduledoc """
  Round-trip Bolty.Types.Point through a real Neo4j connection ahead of building
  AshNeo4j.Type.Point. Covers the four CRSs bolty supports (WGS-84 2D/3D,
  Cartesian 2D/3D), single values and arrays.

  This test deliberately bypasses the AshNeo4j data layer — we want to know
  what the driver itself does before designing any wrapper.
  """
  use ExUnit.Case, async: true

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Sandbox
  alias Bolty.Types.Point

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  defp write_and_read_property(key, value) do
    id = "rt-#{:erlang.unique_integer([:positive])}"
    cypher_create = "CREATE (n:RoundTrip {id: $id, #{key}: $v})"
    cypher_read = "MATCH (n:RoundTrip {id: $id}) RETURN n.#{key} AS v"
    {:ok, _} = Sandbox.run(cypher_create, %{"id" => id, "v" => value})
    {:ok, response} = Sandbox.run(cypher_read, %{"id" => id})
    response |> Bolty.Response.first() |> Map.fetch!("v")
  end

  describe "single Point round-trip" do
    test "WGS-84 2D" do
      sydney = Point.create(:wgs_84, 151.2093, -33.8688)
      assert write_and_read_property("p", sydney) == sydney
    end

    test "WGS-84 3D" do
      sydney = Point.create(:wgs_84, 151.2093, -33.8688, 58.0)
      assert write_and_read_property("p", sydney) == sydney
    end

    test "Cartesian 2D" do
      p = Point.create(:cartesian, 10.0, 20.0)
      assert write_and_read_property("p", p) == p
    end

    test "Cartesian 3D" do
      p = Point.create(:cartesian, 10.0, 20.0, 30.0)
      assert write_and_read_property("p", p) == p
    end
  end

  describe "array of Points round-trip" do
    test "WGS-84 2D — polygon-shaped vertex list (open ring, CCW)" do
      poly = [
        Point.create(:wgs_84, 151.0, -33.5),
        Point.create(:wgs_84, 151.5, -33.5),
        Point.create(:wgs_84, 151.5, -33.0),
        Point.create(:wgs_84, 151.0, -33.0)
      ]

      assert write_and_read_property("poly", poly) == poly
    end

    test "WGS-84 2D — single-point list" do
      lst = [Point.create(:wgs_84, 0.0, 0.0)]
      assert write_and_read_property("poly", lst) == lst
    end
  end

  describe "edges and surprises" do
    test "integer coordinates are cast to floats by Point.create" do
      # Documents the cast — relevant when callers pass integers from JSON or untyped sources.
      p = Point.create(:cartesian, 1, 2)
      assert p.x == 1.0
      assert p.y == 2.0
      assert write_and_read_property("p", p) == p
    end

    test "WGS-84 2D populates both x/y and longitude/latitude" do
      # Round-trip should re-populate longitude/latitude on the way back (unpacker calls Point.create).
      p = Point.create(:wgs_84, 151.2093, -33.8688)
      assert p.longitude == 151.2093
      assert p.latitude == -33.8688
      assert p.x == 151.2093
      assert p.y == -33.8688

      got = write_and_read_property("p", p)
      assert got.longitude == 151.2093
      assert got.latitude == -33.8688
    end
  end
end
