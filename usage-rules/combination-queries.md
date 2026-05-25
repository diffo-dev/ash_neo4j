<!--
SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Combination queries

AshNeo4j supports [Ash's combination queries](https://hexdocs.pm/ash/combination-queries.html) — combining multiple subqueries against the same resource using set operations. All five `Ash.Query.Combination` types are supported: `:base`, `:union`, `:union_all`, `:intersect`, `:except`.

```elixir
require Ash.Query
require Ash.Expr
import Ash.Expr

# Customers served by NBN but not by any peer SIP
Customer
|> Ash.Query.combination_of([
  Ash.Query.Combination.base(filter: expr(in_csa)),
  Ash.Query.Combination.except(filter: expr(in_nsa))
])
|> Ash.read!()
```

The first combination in the list must always be `Ash.Query.Combination.base/1`. Subsequent combinations are applied to the running result set in order.

## Operations

| Operation | Builder | Behaviour |
|---|---|---|
| Base | `Ash.Query.Combination.base/1` | The starting set; required first in the list |
| Union (dedup) | `Ash.Query.Combination.union/1` | Records from the running set ∪ records from this query |
| Union all | `Ash.Query.Combination.union_all/1` | Same as union, with duplicates kept at the Cypher level (collapsed at the Ash record level — see below) |
| Intersect | `Ash.Query.Combination.intersect/1` | Records that appear in both the running set and this query |
| Except | `Ash.Query.Combination.except/1` | Records in the running set that do *not* appear in this query (set difference) |

Mixed operations in a single combination_of are applied in order — `base + union + except` means *(base ∪ second) ∖ third*.

## How AshNeo4j executes combinations

AshNeo4j picks one of two execution paths based on the operation types:

**Native pushdown** — when all subsequent operations are `:union` or all are `:union_all`, the whole combination renders as a single Cypher `CALL { … UNION/UNION ALL … } WITH s OPTIONAL MATCH (s)-[r]-(d) RETURN s, r, d` block. One round trip, server-side set operation.

**In-memory orchestration** — for `:intersect`, `:except`, or any mixed combination involving `:union` + `:union_all` or any of the above with set difference / intersection. Each subquery runs returning just node ids (`id(s) AS sid`), AshNeo4j computes the set operation in Elixir over `MapSet`s, then a final `MATCH (s) WHERE id(s) IN $ids OPTIONAL MATCH (s)-[r]-(d) RETURN s, r, d` fetches the keep-set with enrichment. Worst-case cost is linear in the *subquery result-set size*, not in the underlying node count — fine when each branch returns a handful of nodes, less so when branches return tens of thousands.

Cypher has no native `INTERSECT` or `EXCEPT` operators in Cypher 5, so the in-memory path is the honest implementation. If both subquery result sets are bounded (typical for service-qualification and similar domain queries), the cost is trivial.

## UNION vs UNION_ALL at the record level

Cypher's `UNION ALL` preserves duplicate rows; `UNION` (or `UNION DISTINCT`) deduplicates. **At the Ash record level, AshNeo4j's `consolidate_groups/1` always groups source nodes by primary key** — this is the right behaviour for the OPTIONAL MATCH enrichment pattern, where multiple Cypher rows of the same source node carry different relations into one consolidated record. The consequence: for overlapping branches, `union` and `union_all` return *the same Ash result*. The Cypher-level duplicate-preservation is only observable when querying Cypher directly.

If you need duplicate-aware semantics, drop to Cypher (`AshNeo4j.Sandbox.run/2`).

## Polymorphic resources and cross-subtype combinations

`combination_of` combines subqueries against the **same** Ash resource. To combine queries against different concrete subtypes, model them polymorphically — share a base label via a Diffo or AshNeo4j fragment, and filter by subtype in each subquery. Both subqueries are then against the polymorphic resource (e.g. `Place`), distinguishable by a discriminator filter (`type == :csa`), and AshNeo4j's existing label-scoping handles the polymorphism.

This is the idiomatic shape for peer-resource set-difference queries — for example, NBN's `customers in some CSA but not in any NSA`.

## Limitations

- **Subquery `calculate` is not supported** — AshNeo4j doesn't yet support calculations in combination subqueries' projections (a broader AshNeo4j limit on calculations, not specific to combinations).
- **In-memory ops scale with subquery result size** — `intersect` and `except` (and mixed combinations involving them) materialise each branch's id set in Elixir. Fine at sub-thousand-row scale; document the cost if you're combining branches that return tens of thousands of nodes.
- **`union` vs `union_all` are equivalent at the Ash record level** (see above).
- **Same-resource constraint** — Ash's `combination_of` is single-resource. Cross-resource combinations are modelled polymorphically (see above).

## See also

- `usage-rules/spatial.md` — the spatial work that motivated the combination-queries surface (CSA-EXCEPT-NSA service qualification)
- [Ash combination queries](https://hexdocs.pm/ash/combination-queries.html) — the canonical Ash docs
