# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.GeoTypeChangeTest do
  @moduledoc """
  Updating a geo attribute to a value with a *different* companion shape must
  drop the companions the new value no longer writes. Regression for #287 —
  under 0.8.0 `SET n += {…}` overwrote same-named companions but never removed
  the ones that no longer applied, so a Point↔area transition (on a multi-kind
  attribute) left a stale indexable companion, and a nested geo field going from
  present to absent left a stale dotted sidecar. The canonical `<attr>.json` is
  always overwritten, so the read value is correct — the danger is a stale
  indexable companion corrupting spatial pushdown / a POINT index.
  """
  use ExUnit.Case, async: false

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Cypher
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Place
  require Ash.Query

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  defp shape_companions(id) do
    {:ok, %Bolty.Response{results: [row]}} =
      Cypher.run(
        """
        MATCH (n:Place {uuid: $id})
        RETURN n.`shape.json` AS json, n.`shape.point` AS point,
               n.`shape.bbSW` AS bbsw, n.`shape.bbNE` AS bbne
        """,
        %{"id" => id}
      )

    row
  end

  defp point, do: %Geo.Point{coordinates: {151.25, -33.75}, srid: 4326}

  defp polygon do
    %Geo.Polygon{
      coordinates: [[{151.0, -34.0}, {151.5, -34.0}, {151.5, -33.5}, {151.0, -33.5}, {151.0, -34.0}]],
      srid: 4326
    }
  end

  test "Point -> area drops the stale .point companion (#287)" do
    place = Place |> Ash.create!(%{shape: point()})

    row = shape_companions(place.id)
    assert row["point"] != nil
    assert row["bbsw"] == nil

    Place |> Ash.get!(place.id) |> Ash.update!(%{shape: polygon()})

    row = shape_companions(place.id)
    assert row["point"] == nil, "stale shape.point left after Point -> area"
    assert row["bbsw"] != nil
    assert row["bbne"] != nil
    assert row["json"] != nil

    assert %Geo.Polygon{} = Ash.get!(Place, place.id).shape
  end

  test "area -> Point drops the stale .bbSW/.bbNE companions (#287)" do
    place = Place |> Ash.create!(%{shape: polygon()})

    row = shape_companions(place.id)
    assert row["bbsw"] != nil
    assert row["point"] == nil

    Place |> Ash.get!(place.id) |> Ash.update!(%{shape: point()})

    row = shape_companions(place.id)
    assert row["bbsw"] == nil, "stale shape.bbSW left after area -> Point"
    assert row["bbne"] == nil, "stale shape.bbNE left after area -> Point"
    assert row["point"] != nil
    assert row["json"] != nil

    assert %Geo.Point{} = Ash.get!(Place, place.id).shape
  end

  test "same-family change (Polygon -> different Polygon) keeps companions, only values change (#287)" do
    place = Place |> Ash.create!(%{shape: polygon()})

    bigger = %Geo.Polygon{
      coordinates: [[{150.0, -35.0}, {152.0, -35.0}, {152.0, -33.0}, {150.0, -33.0}, {150.0, -35.0}]],
      srid: 4326
    }

    Place |> Ash.get!(place.id) |> Ash.update!(%{shape: bigger})

    row = shape_companions(place.id)
    assert row["point"] == nil
    assert row["bbsw"] != nil
    assert row["bbne"] != nil
    assert %Geo.Polygon{} = Ash.get!(Place, place.id).shape
  end

  test "nested geo field removed drops its stale dotted sidecar (#287)" do
    with_home = %AshNeo4j.Test.Type.LocatedDogTypedStruct{
      name: "Rex",
      breed: :kelpie,
      home: %Geo.Point{coordinates: {151.2, -33.8}, srid: 4326}
    }

    place = Place |> Ash.create!(%{pet: with_home})

    {:ok, %Bolty.Response{results: [before]}} =
      Cypher.run("MATCH (n:Place {uuid: $id}) RETURN n.`pet.home.point` AS sidecar", %{"id" => place.id})

    assert before["sidecar"] != nil

    without_home = %AshNeo4j.Test.Type.LocatedDogTypedStruct{name: "Rex", breed: :kelpie, home: nil}
    Place |> Ash.get!(place.id) |> Ash.update!(%{pet: without_home})

    {:ok, %Bolty.Response{results: [after_change]}} =
      Cypher.run(
        "MATCH (n:Place {uuid: $id}) RETURN n.pet AS pet, n.`pet.home.point` AS sidecar",
        %{"id" => place.id}
      )

    assert after_change["pet"] != nil, "pet json should still be present"
    assert after_change["sidecar"] == nil, "stale pet.home.point left after the nested home was cleared"

    assert Ash.get!(Place, place.id).pet.home == nil
  end
end
