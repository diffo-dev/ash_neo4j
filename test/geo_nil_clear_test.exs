# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.GeoNilClearTest do
  @moduledoc """
  Updating an `AshGeo.GeoJson` attribute to `nil` must clear all of its on-disk
  companions (`<attr>.json` plus `<attr>.point` for a Point, or
  `<attr>.bbSW`/`<attr>.bbNE` for other geometries). Regression for #283 — under
  0.8.0 the companions were left on the node, so the next read reconstructed the
  geometry and `record.<attr>` came back non-nil.
  """
  use ExUnit.Case, async: false

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Cypher
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Place

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  defp companions(id) do
    {:ok, %Bolty.Response{results: [row]}} =
      Cypher.run(
        """
        MATCH (n:Place {uuid: $id})
        RETURN n.`location.json` AS json, n.`location.point` AS point,
               n.`bounds.json` AS bjson, n.`bounds.bbSW` AS bbsw, n.`bounds.bbNE` AS bbne
        """,
        %{"id" => id}
      )

    row
  end

  test "clearing a Point attribute to nil removes .json and .point companions (#283)" do
    place = Place |> Ash.create!(%{location: %Geo.Point{coordinates: {151.25, -33.75}, srid: 4326}})

    row = companions(place.id)
    assert row["json"] != nil
    assert row["point"] != nil

    Place |> Ash.get!(place.id) |> Ash.update!(%{location: nil})

    row = companions(place.id)
    assert row["json"] == nil, "location.json companion was left on the node"
    assert row["point"] == nil, "location.point companion was left on the node"

    reloaded = Ash.get!(Place, place.id)
    assert reloaded.location == nil
  end

  test "clearing a Polygon attribute to nil removes .json, .bbSW and .bbNE companions (#283)" do
    polygon = %Geo.Polygon{
      coordinates: [[{151.0, -34.0}, {151.5, -34.0}, {151.5, -33.5}, {151.0, -33.5}, {151.0, -34.0}]],
      srid: 4326
    }

    place = Place |> Ash.create!(%{bounds: polygon})

    row = companions(place.id)
    assert row["bjson"] != nil
    assert row["bbsw"] != nil
    assert row["bbne"] != nil

    Place |> Ash.get!(place.id) |> Ash.update!(%{bounds: nil})

    row = companions(place.id)
    assert row["bjson"] == nil, "bounds.json companion was left on the node"
    assert row["bbsw"] == nil, "bounds.bbSW companion was left on the node"
    assert row["bbne"] == nil, "bounds.bbNE companion was left on the node"

    reloaded = Ash.get!(Place, place.id)
    assert reloaded.bounds == nil
  end

  test "clearing a non-geo attribute with nested promoted geo removes the dotted sidecar (#283)" do
    pet = %AshNeo4j.Test.Type.LocatedDogTypedStruct{
      name: "Rex",
      breed: :kelpie,
      home: %Geo.Point{coordinates: {151.2, -33.8}, srid: 4326}
    }

    place = Place |> Ash.create!(%{pet: pet})

    {:ok, %Bolty.Response{results: [before]}} =
      Cypher.run(
        "MATCH (n:Place {uuid: $id}) RETURN n.pet AS pet, n.`pet.home.point` AS sidecar",
        %{"id" => place.id}
      )

    assert before["pet"] != nil
    assert before["sidecar"] != nil

    Place |> Ash.get!(place.id) |> Ash.update!(%{pet: nil})

    {:ok, %Bolty.Response{results: [after_nil]}} =
      Cypher.run(
        "MATCH (n:Place {uuid: $id}) RETURN n.pet AS pet, n.`pet.home.point` AS sidecar",
        %{"id" => place.id}
      )

    assert after_nil["pet"] == nil
    assert after_nil["sidecar"] == nil, "pet.home.point sidecar was left on the node"

    assert Ash.get!(Place, place.id).pet == nil
  end

  test "transitioning location -> bounds in one update clears the old location on disk (#283)" do
    polygon = %Geo.Polygon{
      coordinates: [[{151.0, -34.0}, {151.5, -34.0}, {151.5, -33.5}, {151.0, -33.5}, {151.0, -34.0}]],
      srid: 4326
    }

    place = Place |> Ash.create!(%{location: %Geo.Point{coordinates: {151.25, -33.75}, srid: 4326}})

    Place |> Ash.get!(place.id) |> Ash.update!(%{location: nil, bounds: polygon})

    row = companions(place.id)
    assert row["json"] == nil
    assert row["point"] == nil
    assert row["bbsw"] != nil

    reloaded = Ash.get!(Place, place.id)
    assert reloaded.location == nil
    refute is_nil(reloaded.bounds)
  end
end
