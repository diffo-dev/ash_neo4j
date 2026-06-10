# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.TraverseExistsCountTest do
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

  defp party_at(name, place) do
    {:ok, ref} = PlaceRef |> Ash.Changeset.for_create(:create, %{role: "site", refers_to: place.id}) |> Ash.create()
    {:ok, party} = Party |> Ash.Changeset.for_create(:create, %{name: name, via_place_ref: ref.id}) |> Ash.create()
    party
  end

  # Party -[:HAS_PLACE_REF]-> PlaceRef -[:REFERS_TO]-> Place
  @chain [{:forward, :place_ref}, {:forward, :place}]

  test "exists == true: parties that reach a place through the chain" do
    sydney = Ash.create!(Place, %{name: "Sydney"})
    party_at("Sited Co", sydney)
    Ash.create!(Party, %{name: "Floating Co"})

    names =
      Party
      |> Ash.Query.filter(traverse(^@chain, :exists) == true)
      |> Ash.read!()
      |> Enum.map(& &1.name)

    assert names == ["Sited Co"]
  end

  test "exists == false: parties that reach no place (membership exclusion)" do
    sydney = Ash.create!(Place, %{name: "Sydney"})
    party_at("Sited Co", sydney)
    Ash.create!(Party, %{name: "Floating Co"})

    names =
      Party
      |> Ash.Query.filter(traverse(^@chain, :exists) == false)
      |> Ash.read!()
      |> Enum.map(& &1.name)

    assert names == ["Floating Co"]
  end

  test "count > 0: cardinality threshold reaches the sited party only" do
    sydney = Ash.create!(Place, %{name: "Sydney"})
    party_at("Sited Co", sydney)
    Ash.create!(Party, %{name: "Floating Co"})

    names =
      Party
      |> Ash.Query.filter(traverse(^@chain, :count) > 0)
      |> Ash.read!()
      |> Enum.map(& &1.name)

    assert names == ["Sited Co"]
  end

  test "count == 0: cardinality zero is the no-reach set" do
    sydney = Ash.create!(Place, %{name: "Sydney"})
    party_at("Sited Co", sydney)
    Ash.create!(Party, %{name: "Floating Co"})

    names =
      Party
      |> Ash.Query.filter(traverse(^@chain, :count) == 0)
      |> Ash.read!()
      |> Enum.map(& &1.name)

    assert names == ["Floating Co"]
  end
end
