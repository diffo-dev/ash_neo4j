# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.TraverseAggregateTest do
  @moduledoc """
  Field aggregates in the `traverse/2` projection (#338): `{:min|:max|:avg|:sum, :field}`.

  The `Party -> PlaceRef -> Place` fixtures reach a single `Place` per `Party`,
  so the aggregate runs over a one-node set (its value is that node's) — enough
  to exercise the pushdown render, the scalar comparison, and the empty-set/null
  exclusion. Aggregation over many reached nodes is Neo4j-native behaviour.
  """
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

  setup do
    sydney = Ash.create!(Place, %{name: "Sydney", population: 5_300_000})
    melbourne = Ash.create!(Place, %{name: "Melbourne", population: 5_100_000})
    party_at("Sydney Co", sydney)
    party_at("Melbourne Co", melbourne)
    Ash.create!(Party, %{name: "Floating Co"})
    :ok
  end

  defp names(filtered), do: filtered |> Ash.read!() |> Enum.map(& &1.name) |> Enum.sort()

  test "min: parties whose site population exceeds a threshold" do
    assert names(Ash.Query.filter(Party, traverse(^@chain, {:min, :population}) > 5_200_000)) == ["Sydney Co"]
  end

  test "max: same field, max aggregate" do
    assert names(Ash.Query.filter(Party, traverse(^@chain, {:max, :population}) <= 5_200_000)) == ["Melbourne Co"]
  end

  test "avg: average reached population over (single-node) set" do
    assert names(Ash.Query.filter(Party, traverse(^@chain, {:avg, :population}) >= 5_200_000)) == ["Sydney Co"]
  end

  test "sum: summed reached population" do
    assert names(Ash.Query.filter(Party, traverse(^@chain, {:sum, :population}) > 5_200_000)) == ["Sydney Co"]
  end

  test "empty-set null: min/max/avg over a no-reach source is null and is excluded" do
    # Floating Co reaches no Place → min(population) is null → null > 0 drops it.
    assert names(Ash.Query.filter(Party, traverse(^@chain, {:min, :population}) > 0)) == ["Melbourne Co", "Sydney Co"]
  end

  test "empty-set zero: sum over a no-reach source is 0 (not null), so it can match" do
    # Neo4j's sum() (like count()) returns 0 over an empty set — Floating Co's
    # sum is 0, which satisfies `< 1` where the sited parties' sums do not.
    assert names(Ash.Query.filter(Party, traverse(^@chain, {:sum, :population}) < 1)) == ["Floating Co"]
  end
end
