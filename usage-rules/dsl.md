<!--
SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# DSL

AshNeo4j resources may include an optional `neo4j do ... end` block. All options are optional — omitting the block entirely is valid.

AshNeo4j enforces its conventions at **compile time**. Violations produce clear `Spark.Error.DslError` messages. The checks are: node labels must be `PascalCase`; node property names must be `camelCase`; edge labels must be `MACRO_CASE`; edge direction must be `:incoming` or `:outgoing`; each `relate` entry must reference a declared Ash relationship; `guard` tuples must be valid; all attribute types must be supported.

```elixir
neo4j do
  label :Comment
  relate [{:post, :BELONGS_TO, :outgoing, :Post}]
  guard [{:WRITTEN_BY, :outgoing, :Author}]
  skip [:transient_field]
end
```

## label

Sets the Neo4j node label for this resource. Must be a `PascalCase` atom.

If omitted, the label defaults to the PascalCase short name of the resource module (e.g. `MyApp.Blog.Comment` → `:Comment`). Only set `label` explicitly when you need to override the default.

```elixir
label :BlogComment
```

### Labels per node

Every node is created with **at least two** labels: the domain label and the module label.

- The **domain label** is the PascalCase short name of the Ash domain module (e.g. `MyApp.Blog` → `:Blog`). Applied automatically; cannot be overridden.
- The **module label** is the PascalCase short name of the resource module (e.g. `MyApp.Blog.Comment` → `:Comment`). Always present and always resource-specific.
- The **resource label** (`label` in the DSL) defaults to the module label. Set it explicitly only when a resource fragment overrides the base type (e.g. a `BaseInstance` fragment declares `label :Instance` — all resources that extend it get `:Instance` as an additional label on CREATE).
- The **domain fragment label** is written on CREATE when the Ash domain uses `AshNeo4j.DataLayer.Domain` via a fragment (e.g. a `Telco` fragment contributes `:Telco` to every node in the domain).

So a `MyApp.Access.ShelfInstance` resource, in an `Access` domain that includes a `Telco` fragment, extending `BaseInstance`, will store nodes with `[:Access, :ShelfInstance, :Instance, :Telco]`.

**Reads, updates, and deletes match on `[domain_label, module_label]` only.** This pair uniquely identifies the resource type and prevents one resource from inadvertently reading nodes belonging to another resource that shares the same fragment base label.

Cross-domain relationships between AshNeo4j resources just work — each domain's resources see only their own nodes. `AshNeo4j.DataLayer.Domain` is an opt-in feature for intentional polymorphic graph traversals (e.g. a single query that matches nodes from multiple domains via a shared base label). You do not need it simply because your application spans multiple domains.

The `AshNeo4j.Resource.Info` module exposes label accessors:

- `label/1` — the `label` DSL value; equals `module_label/1` unless a fragment overrides it
- `module_label/1` — always the PascalCase short name of the resource module
- `domain_label/1` — the PascalCase short name of the domain module
- `domain_fragment_label/1` — the label from a domain fragment, or `nil`
- `label_pair/1` — `[domain_label, module_label]` — use this for all MATCH patterns
- `all_labels/1` — the full list written on CREATE

## relate

Declares explicit graph edge mappings for Ash relationships. Each entry is a 4-tuple:

```
{relationship_name, edge_label, edge_direction, destination_label}
```

- `relationship_name` — must match an Ash `relationships` block entry
- `edge_label` — `MACRO_CASE` atom, e.g. `:BELONGS_TO`
- `edge_direction` — `:outgoing` or `:incoming` relative to this resource's node. The convention is that `:outgoing` reads naturally left to right in Cypher ASCII-art notation: `(this)-[:EDGE]->(related)`. For example, a Comment traversing to its Author via `:WRITTEN_BY` outgoing reads as `(:Comment)-[:WRITTEN_BY]->(:Author)`. An Author traversing back to its Comments uses `:incoming` on the same edge — `(:Author)<-[:WRITTEN_BY]-(:Comment)` — meaning "follow WRITTEN_BY edges that point toward me". No reverse edge is created; direction describes which way you traverse the existing edge.
- `destination_label` — `PascalCase` atom for the destination node

```elixir
relate [
  {:post, :BELONGS_TO, :outgoing, :Post},
  {:author, :WRITTEN_BY, :outgoing, :User}
]
```

If `relate` is omitted, AshNeo4j generates defaults: direction is always `:outgoing`, edge label is derived from the Ash relationship type. Provide explicit `relate` entries only when the defaults are wrong for your graph model.

Each `{edge_label, edge_direction, destination_label}` combination must be unique per resource — AshNeo4j uses it to identify which relationship an incoming edge belongs to.

## guard

Prevents destroy actions when matching edges exist. Each entry is a 3-tuple:

```
{edge_label, edge_direction, destination_label}
```

```elixir
guard [{:WRITTEN_BY, :outgoing, :Post}]
```

Guards are evaluated before deletion. If any matching edge is found in the database the destroy action fails. This is in addition to the implicit guards AshNeo4j applies for `allow_nil? false` `belongs_to` relationships.

Use `guard` when a node is expected by other nodes' relationships even if no explicit Ash relationship is defined on this resource.

## skip

Lists attributes that should not be persisted as node properties.

```elixir
skip [:computed_field, :transient_value]
```

Useful for attributes you want available on the struct but that have no meaning in the graph (e.g. values derived at runtime, or loaded from elsewhere).
