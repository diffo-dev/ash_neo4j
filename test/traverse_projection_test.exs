# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.TraverseProjectionTest do
  @moduledoc """
  Read-time polymorphic projection (#329): `AshNeo4j.Calculations.ProjectedTraversal`
  follows `Party -> PlaceRef -> Place` and returns the reached Place — or
  `AshNeo4j.Unknown` when the reached node resolves to no loaded world, or `nil`
  when nothing is reached.
  """
  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Neo4jHelper
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Party
  alias AshNeo4j.Test.Resource.Place
  alias AshNeo4j.Test.Resource.PlaceRef
  alias AshNeo4j.Unknown

  use ExUnit.Case, async: false

  setup_all do
    BoltyHelper.start()
    # worlds/1 resolves against loaded modules; force the ones this asserts on.
    Enum.each([Place], &Code.ensure_loaded!/1)
    :ok
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

  defp projected_place(party) do
    Party |> Ash.get!(party.id) |> Ash.load!(:projected_place) |> Map.get(:projected_place)
  end

  test "projects the reached Place as a concrete record" do
    sydney = Ash.create!(Place, %{name: "Sydney", population: 5_300_000})
    party = party_at("Sydney Co", sydney)

    projected = projected_place(party)

    assert %Place{name: "Sydney", population: 5_300_000} = projected
  end

  test "nil when nothing is reached" do
    {:ok, floating} = Party |> Ash.Changeset.for_create(:create, %{name: "Floating Co"}) |> Ash.create()
    assert projected_place(floating) == nil
  end

  test "AshNeo4j.Unknown when the reached node resolves to no loaded world" do
    sydney = Ash.create!(Place, %{name: "Orphan Site"})
    party = party_at("Orphan Co", sydney)

    # Strip the domain label so the node still matches the (d:Place) hop but its
    # label set no longer resolves to a world — a real reached-but-unresolvable node.
    {:ok, _} = Neo4jHelper.update_node_labels(:Place, %{name: "Orphan Site"}, [], [:SRM])

    projected = projected_place(party)

    assert %Unknown{reason: :no_concrete_world, world: Party} = projected
    assert Unknown.unknown?(projected)
  end
end
