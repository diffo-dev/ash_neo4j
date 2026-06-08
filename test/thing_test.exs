# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.ThingTest do
  @moduledoc false
  use ExUnit.Case, async: false
  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Thing
  alias AshNeo4j.Test.Resource.ThingCategory
  alias AshNeo4j.Test.Resource.ThingNote
  alias AshNeo4j.Test.Resource.ThingTag

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  test "loading a belongs_to returns it when the node has >=2 same-label collection edges (#285)" do
    cat = ThingCategory |> Ash.create!(%{name: "c"})
    tags = for i <- 1..3, do: ThingTag |> Ash.create!(%{value: "t#{i}"})
    notes = for i <- 1..3, do: ThingNote |> Ash.create!(%{body: "n#{i}"})

    thing =
      Thing
      |> Ash.create!(
        %{
          category_id: cat.id,
          tags: Enum.map(tags, & &1.id),
          notes: Enum.map(notes, & &1.id)
        },
        action: :create
      )

    # The :CATEGORISED_BY edge is present in the graph
    assert AshNeo4j.Neo4jHelper.nodes_relate_how?(
             :Thing,
             %{uuid: thing.id},
             :ThingCategory,
             %{uuid: cat.id},
             :CATEGORISED_BY,
             :outgoing
           )

    # Loading only :category must surface it — read-path must not be truncated
    # by a row LIMIT that lands on the edge-expanded result.
    reloaded = Ash.get!(Thing, thing.id, load: [:category])

    assert reloaded.category != nil, "reloaded.category came back nil (read-path truncated by LIMIT)"
    assert reloaded.category.id == cat.id
  end

  test "a row LIMIT counts distinct nodes, not edge rows (#285)" do
    # Each Thing carries several edges (category + 2 tags + 2 notes = 5 edges).
    # The node read RETURNs one row per edge, so a LIMIT applied to those rows
    # would be swallowed by a single node's edges and return fewer than `limit`
    # distinct nodes. This is deterministic regardless of Neo4j edge ordering.
    for n <- 1..3 do
      cat = ThingCategory |> Ash.create!(%{name: "c#{n}"})
      tags = for i <- 1..2, do: ThingTag |> Ash.create!(%{value: "t#{n}-#{i}"})
      notes = for i <- 1..2, do: ThingNote |> Ash.create!(%{body: "no#{n}-#{i}"})

      Thing
      |> Ash.create!(
        %{category_id: cat.id, tags: Enum.map(tags, & &1.id), notes: Enum.map(notes, & &1.id)},
        action: :create
      )
    end

    results = Thing |> Ash.Query.limit(3) |> Ash.read!()

    assert length(results) == 3, "expected 3 distinct nodes, got #{length(results)} (LIMIT truncated edge rows)"
  end
end
