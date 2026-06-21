<!--
SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Graph traversal expressions — `traverse/2` (#321)

`traverse(^hop_chain, projection)` expresses a multi-hop graph traversal as an
`Ash.Expr` value and pushes it down to a single Cypher path pattern. From the
queried node, follow a chain of typed and directed edges, reach the node(s) at
the far end, and use that reached node inside a `filter`.

This is graph-native: a relational data layer models relationships as joins and
has **no notion of a path as an expression value**. So `traverse` isn't
parity work — it's something a graph data layer can offer that the relational
ones structurally cannot. Reach for it before a join-shaped load or an
imperative multi-query walk.

```elixir
require Ash.Query
import Ash.Expr

# A hop chain — each hop is {:forward | :reverse, edge_selector}.
#   :forward — walk an outgoing edge (the queried node is the edge source)
#   :reverse — walk an incoming edge (the queried node is the edge target)
#   edge_selector — an Ash relationship name (resolved on the source resource
#     to its edge label + destination label), or an explicit
#     {:edge, LABEL} / {:edge, LABEL, DEST_LABEL}.
chain = [{:forward, :posts}]

Author
|> Ash.Query.filter(traverse(^chain, :score) > 50)
|> Ash.read!()
```

## Projection — what to pull from the reached set

The second argument (default `:node`) selects the value the reached set
contributes to the expression:

| Projection | Renders to | Use |
|---|---|---|
| `:node` (default) | the reached node | identity / existence |
| a field atom (`:status`, `:location`) | `d.<property>` | compare, or feed to `st_*` / `vector_*` |
| `:exists` | `EXISTS {}` / `NOT EXISTS {}` | membership — spell `== true` / `== false` |
| `:count` | `COUNT { … } <op> n` | cardinality of distinct reached nodes |
| `{:min \| :max \| :avg \| :sum, :field}` | the reached-set aggregate | aggregate, then compare |

```elixir
# spatial composition — "services whose site is within 5 km of a point", one query
Service |> Ash.Query.filter(st_dwithin(traverse(^chain, :location), ^point, 5_000))

# membership / cardinality (#334)
Service |> Ash.Query.filter(traverse(^chain, :exists) == true)
Service |> Ash.Query.filter(traverse(^chain, :count) > 0)

# field aggregate over the reached set (#338)
Party |> Ash.Query.filter(traverse(^chain, {:max, :population}) <= 5_200_000)
```

Ash's own `count()` / `sum()` are inline aggregates welded to a relationship
path and expanded at filter hydration, so they can't nest as
`traverse(count())` — the aggregate is carried as the projection literal
(`:count`, `{:sum, :field}`) instead.

## Pushdown-only, and where it applies

Traversal needs the graph: it can't be computed from argument values, so it has
**no in-memory value**. The data layer applies it exactly in Cypher and excludes
it from the in-memory correctness re-filter. Two consequences:

- It is recognised in **`filter`** in this slice. `sort` (#335),
  `calculate` / policy contexts, and variable-length traversal (`*`, with
  nearest / root / path / all modes) are fast-follows tracked on the open epic
  **#321**.
- A chain that **can't be formed** — an unknown relationship, a missing field,
  a hop that reaches no known type — returns
  `{:error, %AshNeo4j.Error.UnresolvableTraversal{}}`. It **never fabricates an
  edge label** to make the path render.

## Returning a reached value — `ProjectedTraversal`

`traverse` is for **filtering** on a reached node. To **return** the reached
node as a loaded value (late-binding its concrete type at read time), declare an
`AshNeo4j.Calculations.ProjectedTraversal` calculation:

```elixir
calculate :site, :struct,
  {AshNeo4j.Calculations.ProjectedTraversal,
   chain: [{:forward, :place_ref}, {:forward, :place}]}
```

Per record it returns the concrete record, `%AshNeo4j.Unknown{}` (a node was
reached but resolves to no loaded world), `nil` (nothing reached), or
`%Ash.NotLoaded{}` (until loaded). Pattern-match `AshNeo4j.Unknown` alongside
`nil` and concrete values — it means "reached, but couldn't be determined",
distinct from "not fetched yet" (`NotLoaded`) and "absent" (`nil`). Never
collapse it into `nil`.
