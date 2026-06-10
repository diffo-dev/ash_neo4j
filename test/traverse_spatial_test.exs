# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.TraverseSpatialTest do
  @moduledoc false
  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Party
  alias AshNeo4j.Test.Resource.Place
  alias AshNeo4j.Test.Resource.PlaceRef

  use ExUnit.Case, async: true

  require Ash.Query

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  defp geo(lng, lat), do: %Geo.Point{coordinates: {lng, lat}, srid: 4326}

  defp party_at(name, place) do
    {:ok, ref} = PlaceRef |> Ash.Changeset.for_create(:create, %{role: "site", refers_to: place.id}) |> Ash.create()
    {:ok, party} = Party |> Ash.Changeset.for_create(:create, %{name: name, via_place_ref: ref.id}) |> Ash.create()
    party
  end

  test "st_dwithin composed with a 2-hop traversal: parties whose site is within 5 km of a point" do
    sydney = Ash.create!(Place, %{name: "Sydney", location: geo(151.2093, -33.8688)})
    melbourne = Ash.create!(Place, %{name: "Melbourne", location: geo(144.9631, -37.8136)})

    party_at("Sydney Co", sydney)
    party_at("Melbourne Co", melbourne)

    customer = geo(151.2, -33.85)
    # Party -[:HAS_PLACE_REF]-> PlaceRef -[:REFERS_TO]-> Place(location)
    chain = [{:forward, :place_ref}, {:forward, :place}]

    names =
      Party
      |> Ash.Query.filter(st_dwithin(traverse(^chain, :location), ^customer, 5_000))
      |> Ash.read!()
      |> Enum.map(& &1.name)

    assert names == ["Sydney Co"]
  end

  test "a broader threshold catches both parties' sites" do
    sydney = Ash.create!(Place, %{name: "Sydney", location: geo(151.2093, -33.8688)})
    melbourne = Ash.create!(Place, %{name: "Melbourne", location: geo(144.9631, -37.8136)})
    party_at("Sydney Co", sydney)
    party_at("Melbourne Co", melbourne)

    customer = geo(151.2, -33.85)
    chain = [{:forward, :place_ref}, {:forward, :place}]

    names =
      Party
      |> Ash.Query.filter(st_dwithin(traverse(^chain, :location), ^customer, 1_000_000))
      |> Ash.read!()
      |> Enum.map(& &1.name)
      |> Enum.sort()

    assert names == ["Melbourne Co", "Sydney Co"]
  end

  test "st_distance composed with a traversal: parties whose site is under an exact distance" do
    sydney = Ash.create!(Place, %{name: "Sydney", location: geo(151.2093, -33.8688)})
    melbourne = Ash.create!(Place, %{name: "Melbourne", location: geo(144.9631, -37.8136)})
    party_at("Sydney Co", sydney)
    party_at("Melbourne Co", melbourne)

    customer = geo(151.2, -33.85)
    chain = [{:forward, :place_ref}, {:forward, :place}]

    names =
      Party
      |> Ash.Query.filter(st_distance(traverse(^chain, :location), ^customer) < 5_000)
      |> Ash.read!()
      |> Enum.map(& &1.name)

    assert names == ["Sydney Co"]
  end

  test "st_contains composed with a traversal: parties whose site boundary contains a point" do
    sydney_box = %Geo.Polygon{
      coordinates: [[{151.0, -34.0}, {151.4, -34.0}, {151.4, -33.7}, {151.0, -33.7}, {151.0, -34.0}]],
      srid: 4326
    }

    melbourne_box = %Geo.Polygon{
      coordinates: [[{144.8, -38.0}, {145.1, -38.0}, {145.1, -37.7}, {144.8, -37.7}, {144.8, -38.0}]],
      srid: 4326
    }

    sydney = Ash.create!(Place, %{name: "Sydney", bounds: sydney_box})
    melbourne = Ash.create!(Place, %{name: "Melbourne", bounds: melbourne_box})
    party_at("Sydney Co", sydney)
    party_at("Melbourne Co", melbourne)

    point = geo(151.2, -33.85)
    chain = [{:forward, :place_ref}, {:forward, :place}]

    names =
      Party
      |> Ash.Query.filter(st_contains(traverse(^chain, :bounds), ^point))
      |> Ash.read!()
      |> Enum.map(& &1.name)

    assert names == ["Sydney Co"]
  end
end
