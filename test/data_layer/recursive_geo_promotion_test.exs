# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.DataLayer.RecursiveGeoPromotionTest do
  @moduledoc """
  Tests #274's recursive geo-promotion — when a non-Geo attribute (a
  TypedStruct, embedded resource, etc.) contains a `%Geo.*{}` struct
  somewhere in its value tree, the data layer:

    1. JSON-encodes the parent attribute as usual, with the nested
       GeoJSON inline inside the parent's JSON blob (via
       `Util.to_json_safe`'s Geo handling).
    2. Walks the *input* value (pre-Dump) for nested `%Geo.*{}` and
       promotes each one's indexable companion to a node-level
       property at its dotted path.

  Place.pet is the test fixture — a `LocatedDogTypedStruct` with a
  `home: AshGeo.GeoJson` field. The home Point gets promoted to
  `pet.home.point` on the node, indexable via `point.distance` /
  `point.withinBBox` even though it lives nested inside a JSON-stored
  TypedStruct.
  """
  use ExUnit.Case, async: true

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Place
  alias AshNeo4j.Test.Type.LocatedDogTypedStruct

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  describe "nested Geo inside a TypedStruct attribute" do
    test "node carries parent JSON at <attr> + promoted indexable companion at <attr>.home.point" do
      henry = %{
        name: "Henry",
        breed: :groodle,
        home: %Geo.Point{coordinates: {151.2093, -33.8688}, srid: 4326}
      }

      created = Place |> Ash.create!(%{name: "Sydney Henry", pet: henry})

      {:ok, response} =
        Sandbox.run(
          """
          MATCH (n:SRM:Place {uuid: $uuid})
          RETURN
            keys(n) AS keys,
            n.pet AS pet_json,
            n.`pet.home.point` AS home_point
          """,
          %{"uuid" => created.id}
        )

      [row] = response.results
      keys = row["keys"]

      # Parent attribute lands at the bare key as a JSON blob; the
      # nested Geo's indexable companion sits alongside at <attr>.<field>.point.
      assert "pet" in keys
      assert "pet.home.point" in keys
      refute "pet.home.json" in keys
      refute "pet.home" in keys

      # The parent JSON blob contains the nested GeoJSON inline.
      assert row["pet_json"] =~ ~s("name":"Henry")
      assert row["pet_json"] =~ ~s("breed":"groodle")
      assert row["pet_json"] =~ ~s("type":"Point")
      assert row["pet_json"] =~ ~s("coordinates":[151.2093,-33.8688])
      assert row["pet_json"] =~ ~s("bbox":[151.2093,-33.8688,151.2093,-33.8688])

      # The promoted companion is a native Neo4j Point, indexable.
      assert %Bolty.Types.Point{srid: 4326, x: 151.2093, y: -33.8688} = row["home_point"]
    end

    test "read path reconstructs the TypedStruct with the nested Geo intact" do
      henry = %{
        name: "Henry",
        breed: :groodle,
        home: %Geo.Point{coordinates: {151.2093, -33.8688}, srid: 4326}
      }

      created = Place |> Ash.create!(%{name: "Sydney Henry", pet: henry})
      reread = Place |> Ash.get!(created.id)

      assert %LocatedDogTypedStruct{
               name: "Henry",
               breed: :groodle,
               home: %Geo.Point{coordinates: {151.2093, -33.8688}, srid: 4326}
             } = reread.pet
    end

    test "nil pet writes nothing — no parent, no promoted companions" do
      created = Place |> Ash.create!(%{name: "No pet"})

      {:ok, response} =
        Sandbox.run(
          "MATCH (n:SRM:Place {uuid: $uuid}) RETURN keys(n) AS keys",
          %{"uuid" => created.id}
        )

      [row] = response.results
      keys = row["keys"]

      refute "pet" in keys
      refute "pet.home.point" in keys
    end

    test "Cypher pushdown works on the promoted companion — point.distance via n.`pet.home.point`" do
      sydney_henry = %{
        name: "Henry",
        breed: :groodle,
        home: %Geo.Point{coordinates: {151.2093, -33.8688}, srid: 4326}
      }

      melbourne_kipper = %{
        name: "Kipper",
        breed: :labradoodle,
        home: %Geo.Point{coordinates: {144.9631, -37.8136}, srid: 4326}
      }

      sydney_place = Place |> Ash.create!(%{name: "Sydney Place", pet: sydney_henry})
      _melbourne_place = Place |> Ash.create!(%{name: "Melbourne Place", pet: melbourne_kipper})

      {:ok, response} =
        Sandbox.run(
          """
          MATCH (n:SRM:Place)
          WHERE n.`pet.home.point` IS NOT NULL
            AND point.distance(
              n.`pet.home.point`,
              point({longitude: 151.21, latitude: -33.87})
            ) < 5000
          RETURN n.uuid AS uuid
          """,
          %{}
        )

      uuids = Enum.map(response.results, & &1["uuid"])
      assert sydney_place.id in uuids
      assert length(uuids) == 1
    end
  end
end
