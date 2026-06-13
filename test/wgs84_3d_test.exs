# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Wgs84_3DTest do
  @moduledoc """
  WGS-84-3D (#270) Phase 1 — `%Geo.PointZ{}` storage, 3D `st_distance` /
  `st_dwithin` (pushdown + in-memory parity), the strict 2D/3D
  `GeoDimensionMismatch` guard, and `force_2d` as the downward bridge.

  3D `point.distance` is available on Neo4j 5.x, so these run on the default
  pool alongside the 2D spatial tests.
  """
  use ExUnit.Case, async: true

  require Ash.Query

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Geo, as: G
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Place

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  defp pz(lng, lat, h), do: %Geo.PointZ{coordinates: {lng, lat, h}, srid: 4979}
  defp p2(lng, lat), do: %Geo.Point{coordinates: {lng, lat}, srid: 4326}

  # The data layer raises during query-build / dump; Ash wraps it (Ash.Error.*),
  # but the original message is preserved — assert on that.
  defp assert_message(expected, fun) do
    fun.()
    flunk("expected an exception, got none")
  rescue
    e -> assert Exception.message(e) =~ expected
  end

  # The data layer returns (never raises) a Splode error for an unformable
  # query (#350) — assert the returned error's message.
  defp assert_error_message(expected, fun) do
    assert {:error, error} = fun.()
    assert Exception.message(error) =~ expected
  end

  describe "GeoJson dimension-aware srid" do
    test "decodes a 3D Point with srid 4979" do
      json = AshNeo4j.GeoJson.encode!(pz(151.0, -33.0, 50.0))
      assert %Geo.PointZ{coordinates: {151.0, -33.0, 50.0}, srid: 4979} = AshNeo4j.GeoJson.decode!(json)
    end

    test "decodes a 2D Point with srid 4326 (unchanged)" do
      json = AshNeo4j.GeoJson.encode!(p2(151.0, -33.0))
      assert %Geo.Point{coordinates: {151.0, -33.0}, srid: 4326} = AshNeo4j.GeoJson.decode!(json)
    end
  end

  describe "AshNeo4j.Geo.haversine_meters_3d (matches Neo4j's 3D model)" do
    test "pure height difference is the raw metres" do
      assert_in_delta G.haversine_meters_3d({151.0, -33.0, 0.0}, {151.0, -33.0, 1000.0}), 1000.0, 0.001
    end

    test "ground + height combines via mean-height-scaled arc" do
      # measured from Neo4j: 1° lat + 1000 m up ≈ 111332.76 (not Pythagoras' ~111324.8)
      assert_in_delta G.haversine_meters_3d({151.0, -33.0, 0.0}, {151.0, -34.0, 1000.0}), 111_332.76, 0.5
    end
  end

  describe "AshNeo4j.Geo.force_2d (downward bridge)" do
    test "collapses a PointZ to its 2D footprint" do
      assert %Geo.Point{coordinates: {151.0, -33.0}, srid: 4326} = G.force_2d(pz(151.0, -33.0, 50.0))
    end

    test "is a no-op on an already-2D geometry" do
      assert p2(151.0, -33.0) == G.force_2d(p2(151.0, -33.0))
    end
  end

  describe "PointZ storage round-trip" do
    test "a 3D point persists and reads back as %Geo.PointZ{} (srid 4979)" do
      place = Place |> Ash.create!(%{name: "tower-1", tower: pz(151.2093, -33.8688, 45.0)})
      reloaded = Place |> Ash.get!(place.id)
      assert %Geo.PointZ{coordinates: {151.2093, -33.8688, 45.0}, srid: 4979} = reloaded.tower
    end
  end

  describe "3D st_distance / st_dwithin" do
    setup do
      base = Place |> Ash.create!(%{name: "base", tower: pz(151.0, -33.0, 0.0)})
      {:ok, base: base}
    end

    test "st_distance filter ranks by true 3D distance (pushdown + re-filter agree)", %{base: base} do
      # query point directly above base by 1000 m: 3D distance = 1000 m
      q = pz(151.0, -33.0, 1000.0)

      {:ok, near} = Place |> Ash.Query.filter(st_distance(tower, ^q) < 1500) |> Ash.read()
      assert base.id in Enum.map(near, & &1.id)

      {:ok, far} = Place |> Ash.Query.filter(st_distance(tower, ^q) < 500) |> Ash.read()
      refute base.id in Enum.map(far, & &1.id)
    end

    test "st_dwithin works in 3D", %{base: base} do
      q = pz(151.0, -33.0, 1000.0)
      {:ok, hit} = Place |> Ash.Query.filter(st_dwithin(tower, ^q, 1500)) |> Ash.read()
      assert base.id in Enum.map(hit, & &1.id)
    end
  end

  describe "strict dimension policy (#270)" do
    test "3D value against a 2D attribute returns a GeoDimensionMismatch error" do
      assert_error_message "dimension mismatch: a 3D value against a 2D attribute", fn ->
        Place |> Ash.Query.filter(st_distance(location, ^pz(151.0, -33.0, 5.0)) < 1000) |> Ash.read()
      end
    end

    test "2D value against a 3D attribute returns a GeoDimensionMismatch error" do
      assert_error_message "dimension mismatch: a 2D value against a 3D attribute", fn ->
        Place |> Ash.Query.filter(st_distance(tower, ^p2(151.0, -33.0)) < 1000) |> Ash.read()
      end
    end

    test "force_2d bridges: a 3D point's footprint against a 2D area" do
      poly = %Geo.Polygon{
        coordinates: [[{151.0, -34.0}, {151.5, -34.0}, {151.5, -33.0}, {151.0, -33.0}, {151.0, -34.0}]],
        srid: 4326
      }

      place = Place |> Ash.create!(%{name: "csa", bounds: poly})
      antenna = pz(151.2, -33.5, 30.0)

      {:ok, results} =
        Place |> Ash.Query.filter(st_contains(bounds, ^G.force_2d(antenna))) |> Ash.read()

      assert place.id in Enum.map(results, & &1.id)
    end
  end

  describe "3D areal/linear deferred to Phase 2" do
    test "storing a PolygonZ raises Unsupported3DGeometry" do
      polyz = %Geo.PolygonZ{
        coordinates: [[{151.0, -34.0, 0.0}, {151.5, -34.0, 0.0}, {151.5, -33.0, 0.0}, {151.0, -34.0, 0.0}]],
        srid: 4979
      }

      assert_message "3D areal/linear geometry) is not supported yet", fn ->
        Place |> Ash.create!(%{name: "bad", shape: polyz})
      end
    end
  end
end
