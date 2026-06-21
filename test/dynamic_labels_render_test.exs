# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.DynamicLabelsRenderTest do
  @moduledoc """
  The `:$(expr)` dynamic label/type render primitive (#339), proven on the wire
  against the default pool (Neo4j 5.26, where `dynamic_labels?` is true). Covers
  **pattern position** only — node labels and relationship types in
  `MATCH`/`CREATE` — which is what `dynamic_labels?` guarantees on 5.26. (The
  `WHERE n:$(expr)` predicate form is a finer, later capability and is not part of
  this primitive.) The label/type is supplied as a **bound parameter**, never
  interpolated — the injection-safe form. Self-contained: each probe creates and
  `DETACH DELETE`s its nodes in one statement, persisting nothing.
  """
  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Cypher

  use ExUnit.Case, async: false

  setup_all do
    BoltyHelper.start()
    :ok
  end

  test "require_dynamic_labels/0 is :ok on the 5.26 default pool" do
    assert Cypher.require_dynamic_labels() == :ok
  end

  test "dynamic_label/1 binds a runtime node label in a CREATE pattern" do
    label_frag = Cypher.dynamic_label("$label")

    cypher =
      "CREATE (n#{label_frag} {tag: $tag}) " <>
        "WITH n, labels(n) AS ls " <>
        "DETACH DELETE n " <>
        "RETURN ls AS labels"

    response = Bolty.query!(Bolt, cypher, %{"label" => "DynLabelProbe", "tag" => "probe"})

    assert %{"labels" => ["DynLabelProbe"]} = Bolty.Response.first(response)
  end

  test "dynamic_label/1 binds a runtime relationship type in a CREATE pattern" do
    type_frag = Cypher.dynamic_label("$type")

    cypher =
      "CREATE (a)-[r#{type_frag}]->(b) " <>
        "WITH a, b, type(r) AS t " <>
        "DETACH DELETE a, b " <>
        "RETURN t AS type"

    response = Bolty.query!(Bolt, cypher, %{"type" => "DYN_REL_PROBE"})

    assert %{"type" => "DYN_REL_PROBE"} = Bolty.Response.first(response)
  end
end
