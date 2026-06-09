<!--
SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# AGENTS.md — AshNeo4j

AI agent guidance for the AshNeo4j source repository.

## What this project is

AshNeo4j is an `Ash.DataLayer` that stores Ash resources as nodes in a Neo4j graph database.
It is a library published on hex.pm and maintained at `diffo-dev/ash_neo4j`. Its primary consumer
is the Diffo project; upstream bugs found while working in Diffo belong here.

## Before making changes

1. Read `usage-rules.md` — the canonical rules for using AshNeo4j, including naming conventions,
   relationship semantics, aggregate kinds, and the test sandbox.
2. Understand the label system (see **Label system** below) — the label concept is
   a frequent source of bugs and the most important thing to get right.
3. Run `mix test` before and after your change to confirm nothing regressed.

## Fixing bugs

Before writing any fix, review existing test coverage for the affected behaviour. If the bug
has no test, write the failing test first — this confirms the reproduction and guards the fix
against regression. Only then implement the fix and verify the test passes.

## Designing intricate changes — the spelunking pattern

For any change that touches more than one layer (driver / Cypher / data layer / Ash), don't
work top-down or bottom-up alone — work from both ends and meet in the middle (stalagmite +
stalactite). Both ends carry unknowns that compound when you discover them late.

**Bottom (stalagmite) — start with a focused test against the lowest layer that doesn't
involve Ash.** A raw `Bolty.query!` or `AshNeo4j.Sandbox.run` against the driver. This isolates
driver-level surprises (bolty has a history of type / negotiation issues — see [bolty#32](https://github.com/diffo-dev/bolty/issues/32))
before they ripple up through Cast/Dump and the data layer. Cypher-rendering helpers are also
worth bottom testing — assemble the cypher fragment by hand and `Sandbox.run` it.

**Top (stalactite) — write an exploratory Ash-level test with `IO.inspect` in your data
layer callback.** Surfaces Ash-shape assumptions you have wrong (e.g. the `combination_of`
callback being checked against `{:combine, :base}` was a top-down surprise; the actual
`Ash.Query.Combination.t()` types are five, not the three the @type spec suggested). Throw the
test away once it has taught you the shape.

**Meet in the middle.** Once both ends are settled, the connecting commit is small and
focused — write the bridge code, run the existing end tests plus a new end-to-end one through
Ash.

This pattern saved real time on #45 (spatial) and #10 (combination queries). Use it whenever
the change spans more than one layer.

## Project structure

```
lib/
  data_layer.ex                — Ash.DataLayer behaviour: CRUD, aggregates, calculations,
                                 transaction, enrichments (OPTIONAL MATCH → source attributes)
  cypher.ex                    — Cypher string helpers: node/2, relationship/3, expression/5,
                                 parameterized_node/3, render/1, run/1
  cypher/query.ex              — Typed clause structs (Match, Where, Return, …) and builder
                                 functions for every query shape used by the data layer
  query_helper.ex              — Translates Ash.Query (filter, sort, offset, limit) into
                                 a Cypher.Query; entry point is query_nodes/1. sort_terms/2
                                 pushes vector-similarity sorts into ORDER BY expressions
  bolty_helper.ex              — Pool lifecycle + capability detection: current_pool/0,
                                 with_pool/2, policy/1, cypher25?/1 (cached per pool)
  error.ex                     — AshNeo4j.Error.{RequiresCypher25, GeoDimensionMismatch,
                                 Unsupported3DGeometry}
  spatial.ex                   — AshNeo4j.Spatial: POINT index lifecycle (operator-invoked)
  vector.ex                    — AshNeo4j.Vector: VECTOR index lifecycle (operator-invoked)
  types/vector.ex              — AshNeo4j.Type.Vector: embedding attribute (LIST<FLOAT>)
  geo.ex                       — AshNeo4j.Geo: haversine_meters/2 + 3D variant (match
                                 Neo4j point.distance), force_2d/1 (3D→2D projection)
  functions/                   — Ash.Query.Function modules pushed down to Cypher:
                                 st_* (spatial), vector_similarity / vector_cosine_distance,
                                 and vector_math.ex (shared in-memory cosine for evaluate/1)
  resource/info.ex             — All DSL introspection: label/1, module_label/1, domain_label/1,
                                 domain_fragment_label/1, all_labels/1, label_pair/1,
                                 mapping/1, relate/1, translations/1, and relationship helpers
  resource_mapping.ex          — %ResourceMapping{} struct (module, label, module_label,
                                 domain_fragment_label, all_labels, label_pair,
                                 properties, edges, guards, skip)
  edge_descriptor.ex           — %EdgeDescriptor{} struct (relationship, label, direction,
                                 destination_label)
  neo4j_helper.ex              — Low-level node/edge operations via Bolty
  data_layer/cast.ex           — Casts Neo4j return values to Ash types
  data_layer/dump.ex           — Dumps Ash values to Neo4j-compatible primitives
  data_layer/type_classifier.ex — Classifies types as :ash_json (embedded/struct/map) or scalar
  sandbox.ex                   — AshNeo4j.Sandbox: per-test transaction isolation
  util.ex                      — short_name/1, to_camel_case/1, reverse/1
  persisters/
    persist_labels.ex          — Computes and persists domain_label, module_label, label,
                                 domain_fragment_label, all_labels, label_pair
    persist_translations.ex    — Builds attribute → property name keyword list; excludes
                                 belongs_to source attributes and skip attributes
    persist_relate.ex          — Merges explicit relate DSL with default auto-generated edges
    persist_relationship_attributes.ex — Maps source attributes to relationship names
    persist_mapping.ex         — Bakes __ash_neo4j_mapping__/0 onto each resource module
  verifiers/
    verify_labels_pascal_case.ex
    verify_relate.ex
    verify_guard.ex
    verify_properties_camel_case.ex
    verify_enrichable.ex
    verify_attribute_type.ex

test/
  support/resource/            — Test resources (Post, Comment, Author, Specification, …)
  support/srm.ex               — Test domain (Srm)
  blog_test.exs                — CRUD, filter, relationship tests
  aggregate_test.exs           — All aggregate kinds including filtered and expr aggregates
  calculation_test.exs         — Expression calculations
  data_layer/                  — Unit tests for Cast, Dump, TypeClassifier, Info

bench/                         — benchee harnesses (#306): spatial_containment.exs,
                                 bbox_index_probe.exs; bench/README.md records findings
```

## Label system

Every node has several distinct label concepts. Getting them confused is the most common
source of bugs:

| Name | Persisted as | Example | When used |
|---|---|---|---|
| `domain_label` | `:domain_label` | `:Servo` | Written on CREATE; also part of MATCH via `label_pair` |
| `module_label` | `:module_label` | `:ShelfInstance` | Written on CREATE; also part of MATCH via `label_pair` |
| `label` | `:label` | `:Instance` | May differ from `module_label` when a resource fragment declares a base type; written on CREATE only |
| `domain_fragment_label` | `:domain_fragment_label` | `:Telco` | Written on CREATE only — from a domain fragment using `AshNeo4j.DataLayer.Domain`; `nil` when none declared |
| `all_labels` | `:all_labels` | `[:Servo, :ShelfInstance, :Instance, :Telco]` | Full CREATE label list — `[domain_label, module_label, label, domain_fragment_label]` deduped |
| `label_pair` | `:label_pair` | `[:Servo, :ShelfInstance]` | MATCH label list — always `[domain_label, module_label]`; uniquely identifies this resource type |

**Key invariant:** `all_labels` are written on `CREATE`. For `MATCH` / `UPDATE` / `DELETE`,
use `mapping.label_pair` — always `[domain_label, module_label]`. This two-label combination
uniquely identifies the exact resource type and prevents cross-fragment contamination.

`Cypher.node(:s, [:Servo, :ShelfInstance])` produces `"(s:Servo:ShelfInstance)"` — correct.
`Cypher.node(:s, [:Instance])` produces `"(s:Instance)"` — scans every resource extending the same fragment.
`Cypher.node(:s, [:ShelfInstance])` produces `"(s:ShelfInstance)"` — scopes to module but not domain (avoid).

`mapping.label_pair` always holds `[domain_label, module_label]`. Use it for all MATCH patterns.

## Translations (attribute ↔ property name mapping)

`mapping.properties` is a keyword list of `{ash_attribute_name, neo4j_property_name}` pairs
built by `PersistTranslations`. Rules:

- `snake_case` attributes → `camelCase` properties (via `Util.to_camel_case/1`).
- The `:id` attribute is special: its property name is the camelCase of the Ash type's short
  name (e.g. `Ash.Type.UUID` → property `:uuid`). This avoids colliding with Neo4j's internal
  `id` field.
- `belongs_to` source attributes (e.g. `specification_id`) are **excluded** from translations.
  They are not stored as node properties; their values come from `enrichments/3` (reading the
  OPTIONAL MATCH destination node). Do not re-add them to translations.
- Attributes listed in the `skip` DSL option are also excluded.

The `convert_node_to_resource_impl/4` loop iterates translations and reads node properties.
Because `belongs_to` source attributes are excluded, the loop does not touch them — their
values must survive intact from the enrichments map that seeds the accumulator.

## Enrichments (OPTIONAL MATCH → source attributes)

After a read query `MATCH (s:Label) OPTIONAL MATCH (s)-[r]-(d) RETURN s, r, d`, `enrichments/3`
in `DataLayer` processes each `{edge, dest_node}` pair and populates:

- `belongs_to` relationships: sets `source_attribute` (e.g. `specification_id`) from
  `dest_node.properties[destination_property]`.
- `has_one` reverse relationships: sets `destination_attribute` from source node property.
- `many_to_many` relationships: converts dest_node to a resource struct and appends to a list.

The lookup uses `mapping.edges` (from `mapping.module`). If an edge returned by the OPTIONAL
MATCH has no matching entry in `mapping.edges` (wrong label, wrong direction, or missing relate
entry), `enrichments/3` silently returns `acc` unchanged and the source attribute remains nil.

`edge_direction/2` determines direction by comparing `dest_node.id` with `edge.start` /
`edge.end`:
- `dest_node.id == edge.start` → `:incoming` (destination is the start of the edge)
- `dest_node.id == edge.end` → `:outgoing` (destination is the end of the edge)

## PersistRelate: explicit vs default edges

`PersistRelate` builds `mapping.edges` from two sources:

1. **Explicit entries** — the `relate` list in the resource's `neo4j do` block:
   `{relationship_name, edge_label, direction, destination_label}`.
2. **Default entries** — auto-generated for any Ash relationship that has no explicit entry.
   Default edge label = `String.upcase(relationship.type)` (e.g. `:BELONGS_TO`), default
   destination label = last segment of `relationship.destination` module name.

Explicit entries always take precedence. If a relationship is declared in a fragment's
`neo4j do` block, check whether the extending resource's `relate` DSL correctly merges those
entries — a mismatch between the explicit edge label and the default generates a wrong label
in `mapping.edges`, causing enrichments to silently fail.

## Aggregate execution paths

`run_aggregate_for_ids/6` selects one of four paths based on the aggregate's properties:

| Condition | Path | Description |
|---|---|---|
| `aggregate.field` is an `Ash.Query.Calculation` | expr path | Loads full dest records, evaluates Ash expression per record in Elixir |
| `aggregate_has_filter?(aggregate)` is true | filtered path | Loads full dest records, applies `Ash.Filter.Runtime.filter_matches`, computes aggregate in Elixir |
| field type is `:ash_json` (embedded/struct/map) | embedded path | Runs `collect(d.prop)` in Cypher, casts each raw JSON value via `Cast.cast/3` in Elixir |
| otherwise | Cypher path | Fully pushed down: `COUNT`, `SUM`, `AVG`, `MIN`, `MAX`, `collect`, `head(collect(...))` |

`aggregate_has_filter?` treats `%Ash.Filter{expression: true}` as "no filter" (Ash always
attaches a trivial filter to unfiltered aggregates). Do not change this sentinel check.

## Spatial storage, dimensions & indexing

Geometries (`AshGeo.GeoJson` / `GeoAny`, carrying `%Geo.*{}`) store as canonical RFC 7946
GeoJSON `STRING` at `<attr>.json`, plus **indexable scalar companions**:

- **Point / PointZ** → a single native Neo4j `POINT` at `<attr>.point` (a 3D PointZ is a
  native 3D POINT, srid 4979). This is what `point.distance` reads.
- **Everything else** (LineString, Polygon, Multi*) → bounding-box corners `<attr>.bbSW` /
  `<attr>.bbNE`, which `point.withinBBox` reads.
- Geometries nested in a TypedStruct / embedded resource are promoted to a node-level dotted
  property (`<attr>.<field>.point` etc.) so they stay indexable.

**Strict dimension policy (#270).** Mixing 2D and 3D operands raises
`AshNeo4j.Error.GeoDimensionMismatch` (Neo4j silently returns `null` for mixed CRS, so we
refuse). Bridge explicitly with `AshNeo4j.Geo.force_2d/1` (collapse a 3D operand to its 2D
footprint). 3D areal/linear geometry raises `AshNeo4j.Error.Unsupported3DGeometry` — deferred
to Phase 2.

**In-memory math must match the pushdown.** `st_distance` / `st_dwithin` push down to Neo4j
`point.distance` inside filters but evaluate `AshNeo4j.Geo.haversine_meters/2` (+ the 3D
variant) elsewhere (`order_by`, `calculate`). They MUST agree numerically — the same trap as
the vector `evaluate/1` one below — so the haversine uses the WGS-84 **equatorial** radius
Neo4j uses (not the mean radius), and the 3D variant mean-height-scales the arc.

**Index effectiveness (#311 / #306 — don't re-derive this).** `AshNeo4j.Spatial.create_index`
picks companion suffixes by geometry shape: point/point_z → `.point`, areal → `.bbSW`/`.bbNE`
(a `:point_z` building `.bbSW`/`.bbNE` indexes was the #311 bug — a `%Geo.PointZ{}` never
writes those, so distance went unindexed).

- `st_dwithin` (`point.distance`) is **well served** by the POINT index — plans
  `NodeIndexSeekByRange`, ~6–7× at N=10k, near-constant-time.
- `st_contains` containment uses the **reformulated** `within_bbox` form
  `point.withinBBox(n.bbSW, worldSW, $p) AND point.withinBBox(n.bbNE, $p, worldNE)`, which
  keeps the **indexed corner as the probe** so it plans `NodeIndexSeekByRange`. The natural
  form `point.withinBBox($p, n.bbSW, n.bbNE)` puts the indexed props in the *box* position and
  forces a `NodeByLabelScan` — **do not "simplify" it back.** Even reformulated, containment
  caps near ~1.3× (a single-corner quadrant seek). A "max-extent" bound is infeasible for the
  real CSA workload (uniform in homes-passed, not area — the NT is one CSA); ≥3× containment
  needs an adaptive tile / B-rep sub-graph model (epic #314).
- Benchmarks live in `bench/`; `bench/README.md` records the numbers and methodology.

## Cypher.Query builders

Every query shape used by the data layer has a typed builder in `Cypher.Query`. Builders
return `%Cypher.Query{clauses: [...], params: %{}}` structs that `Cypher.render/1` turns into
a `{cypher_string, params}` tuple for `Cypher.run/1`.

`Cypher.node(variable, labels)` takes a list of label atoms and produces `"(var:L1:L2)"`.
`Cypher.parameterized_node/3` does the same with a property map for parameterized MATCH patterns.

All MATCH/UPDATE/DELETE builders accept `atom() | [atom()]` for source label parameters — pass
`mapping.label_pair` (a list) for all resource operations. Single-atom callers still work for
destination labels (which remain a single label in most patterns).

The aggregate builders (`aggregate_per_record`, `aggregate_total`, `related_nodes`) use a
`labels_string/1` private helper to render `[domain, module]` as `"Domain:Module"` inside
string-interpolated Cypher patterns — `"(s:#{labels_string(label_pair)})"`. When modifying
aggregate builders, use `labels_string/1` for the source pattern, not direct atom interpolation.

## Running tests

Tests require a running Neo4j instance. Pools are configured in `config/test.exs` (the
preferred config method — the old `BOLT_URL`-style env var is deprecated). The primary
`Bolt` pool targets a Neo4j 5.x server; a second `Bolt6` pool targets Neo4j 2026.05 (Bolt
6.0 / Cypher 25) for the version-gated tests. `AshNeo4j.Sandbox` wraps each test in a
transaction that rolls back on completion.

```sh
mix test                          # full suite (excludes :show_neo4j, :bolt6, :cypher25)
mix test test/blog_test.exs       # single file
mix test test/blog_test.exs:LINE  # single test
mix test --max-failures 5         # stop early
mix test --include cypher25       # also run the Cypher 25 vector tests (needs the Bolt6 pool)
```

### Pool routing and version tags

The data layer talks to `AshNeo4j.BoltyHelper.current_pool/0` (default `Bolt`). A test routes
its queries — and the `cypher25?/1` / `policy/1` capability checks — to another pool with
`Process.put(:ash_neo4j_pool, Bolt6)` in `setup`, or `BoltyHelper.with_pool/2` for code in a
separate process (e.g. an `on_exit`). The sandbox holder captures the pool at `checkout/0`.

- `:cypher25` — needs a Neo4j ≥ 2025.06 server (the `Bolt6` pool). Tag vector/Cypher-25 tests
  with it; excluded by default. Run `async: false` (the pool is small and the sandbox holds a
  connection per test).
- `:bolt6` — reserved for tests that genuinely require the Bolt 6.0 protocol (vectors do not —
  see the vector gotcha below).

**Start a long-lived pool from `test_helper.exs`, never a per-test `setup`.** `Bolty.start_link/1`
links the pool to the calling process, so starting it inside a test ties the pool's lifetime to
that one test — later tests then hit a dead pool (`:closed` / "no process"). `setup_all` is
longer-lived than `setup` but `test_helper.exs` (whole-run) is the right place for a shared pool.

The sandbox uses `Process` dictionary flags (`ash_neo4j_in_sandbox_tx`,
`ash_neo4j_tx_stack`). Tests that bypass the sandbox or start their own transactions may
interfere with isolation — check the sandbox implementation before adding transaction logic
in tests.

## Raising upstream bugs

When a bug is found in a dependency (Bolty, Ash, Spark), raise a GitHub issue on that
repository. Use **diffo issue #125** as the style reference:

- **## Description** — explain what the system does, what the code path is, and where it
  breaks. Include a short Cypher or Elixir snippet if it makes the failure concrete.
- **## What we need** — state the correct behaviour plainly.
- **## Why it matters** — explain the practical impact.

Do not attempt to locate or fix the root cause in the dependency. Add useful hypotheses
as a follow-up comment, then leave it with the upstream maintainers.

## Common agent mistakes

- **Not using `mapping.label_pair` for MATCH.** All read, update, delete, and aggregate queries
  must use `mapping.label_pair` (`[domain_label, module_label]`) as the source node pattern.
  Using `mapping.label` alone matches every resource that extends the same fragment. Using
  `mapping.module_label` alone (without domain) risks collisions across domains.

- **Re-adding `belongs_to` source attributes to translations.** They are intentionally excluded
  by `PersistTranslations`. Their values come from enrichments (the OPTIONAL MATCH result).
  Including them in translations would cause the property-read loop to overwrite the
  enriched value with nil (the attribute has no corresponding node property).

- **Assuming `Verifier.get_option(dsl, [:neo4j], :relate, [])` picks up fragment DSL options.**
  `get_entities` picks up entities from fragments; option merging behaviour for `relate` (a
  list option) must be verified separately. If a fragment's explicit `relate` entries are not
  visible, `PersistRelate` generates default edges with wrong labels (e.g. `:BELONGS_TO`
  instead of `:SPECIFIED_BY`), causing enrichments to silently fail.

- **Using a single label in aggregate Cypher builders** (`aggregate_per_record`,
  `aggregate_total`, `related_nodes`). These use `"(s:#{labels_string(source_label)})"` with a
  `labels_string/1` helper. Always pass `mapping.label_pair` as the source label here too.

- **Registering a transformer under `persisters:`** and expecting `before?`/`after?` ordering
  relative to other transformers to be honoured. Persisters always run after ALL transformers.
  Ordering declarations that target transformers from a persister are silently ignored.

- **Using `List.delete/2` to filter domain labels** from destination node labels. It removes
  only the first occurrence. If the source domain label happens to match a destination node
  label, only one instance is removed. Prefer `List.delete_at` or label filtering by explicit
  set membership when precision matters.

- **Treating `domain_label` alone as a MATCH label.** The domain label is part of `label_pair`
  and is used in MATCH, but always paired with `module_label`. Matching on domain label alone
  would return every node in the domain, not just the target resource.

- **Forgetting to update `relation_read` in `Cypher.Query`** when changing MATCH label logic.
  The `relationship_read/7` builder emits a separate `MATCH (s:SrcLabel)-[r:EdgeLabel]-(d:DestLabel)`
  pattern. It must use the same multi-label source pattern as `node_read`.

- **Changing `aggregate_has_filter?` sentinel without understanding Ash's trivial filter.**
  Ash attaches `%Ash.Filter{expression: true}` to every aggregate, even unfiltered ones. The
  check `%Ash.Filter{expression: true} -> false` is intentional — it means "no user filter".
  Removing or loosening it routes all aggregates through the Elixir path unnecessarily.

- **Modifying `Cypher.render/1` to reorder clauses.** The clause list is ordered; render
  outputs them in insertion order. Query correctness depends on this ordering. Always add
  clauses in the correct semantic position in the builder, not in render.

- **Giving a pushed-down query function an `evaluate/1` that returns `:unknown`.** The data
  layer **always re-applies the filter in-memory** via `Ash.Filter.Runtime.filter_matches`
  after the Cypher read (`filter_matches/3` in `DataLayer`) — the pushdown is treated as an
  over-selecting prefilter. A custom `Ash.Query.Function` (e.g. `vector_similarity`) whose
  `evaluate/1` returns `:unknown` will have all its filtered rows **dropped** by that re-filter,
  even though the Cypher `WHERE` was correct (symptom: correct Cypher, empty result; a `sort`
  using the same function still "works" because there's no filter to re-apply). Implement
  `evaluate/1` to compute the real value, and make it **numerically match the pushdown** —
  e.g. Neo4j's `vector.similarity.cosine` is normalised `(1 + raw_cosine)/2`, so the in-memory
  cosine must use the same normalisation (`AshNeo4j.Functions.VectorMath`) or the re-filter
  disagrees with the `WHERE` threshold.

- **Storing a native `%Bolty.Types.Vector{}` as a node property.** Neo4j cannot persist the
  Bolt 6.0 VECTOR type as a property — `CREATE (n {embedding: $vector})` errors. Embeddings are
  stored as `LIST<FLOAT>` (`AshNeo4j.Type.Vector.dump_to_native/2`), which is what
  `vector.similarity.cosine/2` operates on and what the vector index indexes. The native VECTOR
  type is a query-parameter wire type only. Consequently vector search is gated on **Cypher 25
  (≥ 2025.06)**, not Bolt 6.0 — it works over Bolt 5.8.
