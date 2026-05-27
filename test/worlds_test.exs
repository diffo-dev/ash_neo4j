# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.WorldsTest do
  @moduledoc """
  `AshNeo4j.worlds/1` (#273) — projects a node's labels back to the
  `(domain, resource)` worlds it participates in, outermost-first.

  Real-read tests confirm the labels survive onto `__metadata__` and
  resolve to the queried world. Synthetic-record tests drive the
  resolver directly (grouping, outermost-per-domain, cross-domain
  ordering) against the real loaded resources without needing a
  polymorphic write.
  """
  use ExUnit.Case, async: true

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Resource.Info, as: ResourceInfo
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.{Blueprint, Place, TypedInstance}

  setup_all do
    BoltyHelper.start()
    # worlds/1 resolves against *loaded* modules (an unloaded world is left
    # unknown). In a real app the resources are loaded; here we force the
    # ones these tests assert on so the scan is deterministic regardless of
    # async load timing.
    Enum.each([Blueprint, Place, TypedInstance], &Code.ensure_loaded!/1)
    :ok
  end

  # Build a record-shaped value with chosen node labels, mirroring what the
  # data layer attaches on read (labels arrive as strings from Neo4j).
  defp node_with(labels), do: %{__metadata__: %{labels: Enum.map(labels, &to_string/1)}}

  describe "worlds/1 — resolver (synthetic label sets)" do
    test "a single-world node resolves to its one (domain, resource)" do
      assert AshNeo4j.worlds(node_with([:SRM, :Place])) == [{AshNeo4j.Test.SRM, Place}]
    end

    test "a fragment label in the set still resolves the concrete resource" do
      assert AshNeo4j.worlds(node_with([:SRM, :TypedInstance, :Type])) ==
               [{AshNeo4j.Test.SRM, TypedInstance}]
    end

    test "within a domain, only the outermost (most-specific) resource is returned" do
      # Labels of both Place and TypedInstance, same domain — TypedInstance
      # has the larger label set, so it wins; Place is not also returned.
      assert AshNeo4j.worlds(node_with([:SRM, :Place, :TypedInstance, :Type])) ==
               [{AshNeo4j.Test.SRM, TypedInstance}]
    end

    test "resolves N worlds across domains, outermost-first" do
      # Blueprint (Provider, 3 labels incl. the :MyTestDomain domain-fragment
      # label) is more nuanced than Place (SRM, 2 labels), so it sorts first.
      labels = ResourceInfo.all_labels(Blueprint) ++ ResourceInfo.all_labels(Place)

      assert AshNeo4j.worlds(node_with(labels)) == [
               {AshNeo4j.Test.Provider, Blueprint},
               {AshNeo4j.Test.SRM, Place}
             ]
    end

    test "labels matching no loaded resource resolve to no world" do
      assert AshNeo4j.worlds(node_with([:Nope, :AlsoNope])) == []
    end

    test "a record without read metadata yields []" do
      assert AshNeo4j.worlds(%Geo.Point{coordinates: {0.0, 0.0}, srid: 4326}) == []
      assert AshNeo4j.worlds(%{}) == []
      assert AshNeo4j.worlds(nil) == []
    end
  end

  describe "worlds/1 — real reads carry resolvable labels" do
    setup do
      Sandbox.checkout()
      on_exit(&Sandbox.rollback/0)
    end

    test "a queried Place resolves to its own world" do
      place = Place |> Ash.create!(%{name: "world read"})
      reread = Place |> Ash.get!(place.id)

      assert AshNeo4j.worlds(reread) == [{AshNeo4j.Test.SRM, Place}]
    end

    test "a fragmented resource read resolves through its fragment label" do
      ti = TypedInstance |> Ash.create!(%{name: "ti world read"})
      reread = TypedInstance |> Ash.get!(ti.id)

      assert AshNeo4j.worlds(reread) == [{AshNeo4j.Test.SRM, TypedInstance}]
    end
  end
end
