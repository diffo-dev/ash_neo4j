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
2. Understand the label system (see **Label system** below) — the three-level label concept is
   a frequent source of bugs and the most important thing to get right.
3. Run `mix test` before and after your change to confirm nothing regressed.

## Project structure

```
lib/
  data_layer.ex                — Ash.DataLayer behaviour: CRUD, aggregates, calculations,
                                 transaction, enrichments (OPTIONAL MATCH → FK attributes)
  cypher.ex                    — Cypher string helpers: node/2, relationship/3, expression/5,
                                 parameterized_node/3, render/1, run/1
  cypher/query.ex              — Typed clause structs (Match, Where, Return, …) and builder
                                 functions for every query shape used by the data layer
  query_helper.ex              — Translates Ash.Query (filter, sort, offset, limit) into
                                 a Cypher.Query; entry point is query_nodes/1
  resource/info.ex             — All DSL introspection: label/1, module_label/1, labels/1,
                                 mapping/1, relate/1, translations/1, and relationship helpers
  resource_mapping.ex          — %ResourceMapping{} struct (module, label, module_label,
                                 labels, properties, edges, guards, skip)
  edge_descriptor.ex           — %EdgeDescriptor{} struct (relationship, label, direction,
                                 destination_label)
  neo4j_helper.ex              — Low-level node/edge operations via Bolty
  data_layer/cast.ex           — Casts Neo4j return values to Ash types
  data_layer/dump.ex           — Dumps Ash values to Neo4j-compatible primitives
  data_layer/type_classifier.ex — Classifies types as :ash_json (embedded/struct/map) or scalar
  sandbox.ex                   — AshNeo4j.Sandbox: per-test transaction isolation
  util.ex                      — short_name/1, to_camel_case/1, reverse/1
  persisters/
    persist_labels.ex          — Computes and persists domain_label, module_label, label, labels
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
```

## Label system

Every node has three distinct label concepts. Getting them confused is the most common
source of bugs:

| Name | Persisted as | Example | When used |
|---|---|---|---|
| `domain_label` | `:domain_label` | `:Servo` | Written on CREATE only — never used to match |
| `module_label` | `:module_label` | `:ShelfInstance` | Written on CREATE; should be part of MATCH |
| `label` | `:label` | `:Instance` | May differ from module_label when a fragment declares a base type label; used as the MATCH label |
| `labels` | `:labels` | `[:Servo, :ShelfInstance, :Instance]` | Full CREATE label list — `[domain_label | [module_label, label] |> Enum.uniq()]` |

**Key invariant:** `labels` (all three) are written on `CREATE`. For `MATCH` / `UPDATE` /
`DELETE`, the domain label is never used. When the resource uses a fragment that contributes a
different `label` (e.g. `:Instance` from `BaseInstance`), reading with only that label matches
nodes from all resources that extend the same fragment — a correctness bug. Use
`[module_label, label]` (deduped) for MATCH so reads are scoped to the exact resource.

`Cypher.node(:s, [module_label, label])` produces `"(s:ShelfInstance:Instance)"` — correct.
`Cypher.node(:s, [label])` produces `"(s:Instance)"` — scans the whole fragment family.

`ResourceInfo.module_label/1` and `mapping.module_label` always hold the resource-specific label.

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

## Enrichments (OPTIONAL MATCH → FK attributes)

After a read query `MATCH (s:Label) OPTIONAL MATCH (s)-[r]-(d) RETURN s, r, d`, `enrichments/3`
in `DataLayer` processes each `{edge, dest_node}` pair and populates:

- `belongs_to` relationships: sets `source_attribute` (e.g. `specification_id`) from
  `dest_node.properties[destination_property]`.
- `has_one` reverse relationships: sets `destination_attribute` from source node property.
- `many_to_many` relationships: converts dest_node to a resource struct and appends to a list.

The lookup uses `mapping.edges` (from `mapping.module`). If an edge returned by the OPTIONAL
MATCH has no matching entry in `mapping.edges` (wrong label, wrong direction, or missing relate
entry), `enrichments/3` silently returns `acc` unchanged and the FK attribute remains nil.

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

## Cypher.Query builders

Every query shape used by the data layer has a typed builder in `Cypher.Query`. Builders
return `%Cypher.Query{clauses: [...], params: %{}}` structs that `Cypher.render/1` turns into
a `{cypher_string, params}` tuple for `Cypher.run/1`.

`Cypher.node(variable, labels)` takes a list of label atoms and produces `"(var:L1:L2)"`.
`Cypher.parameterized_node/3` does the same with a property map for parameterized MATCH patterns.

When adding a new builder or modifying an existing one, keep `label` parameters as `atom()`
for single-label callers. If a builder needs to support multi-label MATCH (e.g. after the
#257 fix), update the typespec to `atom() | [atom()]` and handle both.

The aggregate builders (`aggregate_per_record`, `aggregate_total`, `related_nodes`) use direct
string interpolation for the source node pattern — `"(s:#{source_label})"`. To support
multi-label source MATCH these must be updated alongside the read builders.

## Running tests

Tests require a running Neo4j instance (configured in `config/runtime.exs` via `BOLT_URL`
or similar). `AshNeo4j.Sandbox` wraps each test in a transaction that rolls back on completion.

```sh
mix test                          # full suite
mix test test/blog_test.exs       # single file
mix test test/blog_test.exs:LINE  # single test
mix test --max-failures 5         # stop early
```

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

- **Matching on `mapping.label` alone** when the resource uses a fragment with a different base
  type label (e.g. `:Instance`). MATCH must use `[mapping.module_label, mapping.label]` so
  reads are scoped to the exact resource module. `mapping.label` alone matches every resource
  that extends the same fragment.

- **Re-adding `belongs_to` source attributes to translations.** They are intentionally excluded
  by `PersistTranslations`. Their values come from enrichments (the OPTIONAL MATCH result).
  Including them in translations would cause the property-read loop to overwrite the
  enriched value with nil (the attribute has no corresponding node property).

- **Assuming `Verifier.get_option(dsl, [:neo4j], :relate, [])` picks up fragment DSL options.**
  `get_entities` picks up entities from fragments; option merging behaviour for `relate` (a
  list option) must be verified separately. If a fragment's explicit `relate` entries are not
  visible, `PersistRelate` generates default edges with wrong labels (e.g. `:BELONGS_TO`
  instead of `:SPECIFIED_BY`), causing enrichments to silently fail.

- **Using `mapping.label` in aggregate Cypher builders** (`aggregate_per_record`,
  `aggregate_total`, `related_nodes`). These use `"(s:#{source_label})"` directly and have the
  same fragment-scoping bug as the read builders. Fix them alongside the read path.

- **Registering a transformer under `persisters:`** and expecting `before?`/`after?` ordering
  relative to other transformers to be honoured. Persisters always run after ALL transformers.
  Ordering declarations that target transformers from a persister are silently ignored.

- **Using `List.delete/2` to filter domain labels** from destination node labels. It removes
  only the first occurrence. If the source domain label happens to match a destination node
  label, only one instance is removed. Prefer `List.delete_at` or label filtering by explicit
  set membership when precision matters.

- **Treating `domain_label` as a MATCH label.** The domain label is written on CREATE so that
  domain-scoped traversals work, but it is never used for reading. Matching on it would return
  every node in the domain, not just the target resource.

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
