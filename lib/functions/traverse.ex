# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.Traverse do
  @moduledoc """
  A multi-hop graph traversal as an `Ash.Expr` value, pushed down to a Cypher
  path pattern (#321).

  From the queried node, follow a chain of typed/directed edges and reach the
  node(s) at the far end — then use that reached node inside a `filter`:

      # reached-node field comparison
      Service
      |> Ash.Query.filter(traverse(^chain, :status) == "active")
      |> Ash.read!()

      # compose with spatial — "services whose site is within 5 km of a point"
      Service
      |> Ash.Query.filter(st_dwithin(traverse(^chain, :location), ^point, 5_000))
      |> Ash.read!()

      # membership / cardinality over the reached set (#334)
      Service |> Ash.Query.filter(traverse(^chain, :exists) == true)   # reaches a node
      Service |> Ash.Query.filter(traverse(^chain, :exists) == false)  # reaches none
      Service |> Ash.Query.filter(traverse(^chain, :count) > 0)        # cardinality

  ## Arguments

    * `hop_chain` — a list of hops, each `{:forward | :reverse, edge_selector}`.
      `:forward` walks an outgoing edge, `:reverse` an incoming one.
      `edge_selector` is an Ash **relationship name** (atom, resolved on the
      source resource to its edge label + destination label) or an explicit
      `{:edge, label}` / `{:edge, label, dest_label}`.
    * `projection` (optional, default `:node`) — what to pull from the reached
      set:
        * `:node` (default) — the reached node itself
        * a field atom (e.g. `:status`, `:location`) — a field on the reached
          node, to compare or feed to `st_dwithin`/`vector_similarity`
        * `:exists` — membership; renders to `EXISTS {}` / `NOT EXISTS {}`,
          spelled `== true` / `== false`
        * `:count` — cardinality of distinct reached nodes; renders to
          `COUNT { … } <op> n`

  Ash's `count()`/`sum()`/… are inline aggregates welded to a relationship path
  and expanded at filter hydration, so they can't nest as `traverse(count())`;
  the aggregate is carried as a projection literal (`:count`) instead.

  ## Pushdown only

  Traversal needs the graph, so it cannot be computed from argument values
  alone — `evaluate/1` returns `:unknown` and the data layer must push it down
  to Cypher. In this first slice it is recognised in `filter`; `sort`/
  `calculate`/policy contexts are a fast-follow.
  """
  use Ash.Query.Function, name: :traverse, predicate?: false

  # traverse(hop_chain) | traverse(hop_chain, projection)
  def args, do: [[:any], [:any, :any]]

  def returns, do: [:any]

  # No argument-only evaluation — traversal is a graph operation, resolved by
  # pushdown. `:unknown` signals the data layer must handle it (or the query
  # fails fast in an unsupported context).
  def evaluate(_), do: :unknown

  @doc false
  # Marks this as a **pushdown-only** expression: it needs the graph and has no
  # in-memory value, so the data layer applies it exactly in Cypher and excludes
  # it from the in-memory correctness re-filter (see `drop_pushdown_only/1`).
  def ash_neo4j_pushdown_only?, do: true
end
