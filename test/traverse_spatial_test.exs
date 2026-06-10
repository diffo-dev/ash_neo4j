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
end
