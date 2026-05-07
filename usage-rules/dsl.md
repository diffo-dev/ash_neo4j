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

Every node is created with **at least two** labels: the domain label and the resource label.

- The **domain label** is the PascalCase short name of the Ash domain module (e.g. `MyApp.Blog` → `:Blog`). It is applied automatically and cannot be overridden.
- The **resource label** is the value of `label` in the `neo4j do` block, defaulting to the PascalCase short name of the resource module. This is the label used to match nodes on read, update, and destroy.

When a resource uses a fragment that declares its own `label`, that fragment label is also written on CREATE as an additional label. A resource using `BaseInstance` (which declares `label :Instance`) will store nodes with `[:Domain, :ResourceName, :Instance]`. This enables polymorphic graph traversals — a relationship targeting `:Instance` will match any resource that extends `BaseInstance`, regardless of domain. A resource can only extend one fragment this way since full resources are not fragments.

Because reads match on the base type label (`:Instance`), `Provider.Instance.read()` and `Access.Shelf.read()` both issue `MATCH (n:Instance)` — they will return the same nodes from the graph. This is intentional: the Provider domain provides a broad cross-domain API, while domain-specific resources like `Access.Shelf` provide a typed view into the same underlying nodes. Use domain-specific resources when you need a typed API; use the base resource when you need to traverse or query across domains.

The `AshNeo4j.Resource.Info` module exposes three distinct label accessors:

- `label/1` — the match label used for read/update/destroy (e.g. `:Instance` if set by a fragment)
- `module_label/1` — the label derived from the resource module's own short name (e.g. `:Shelf`)
- `labels/1` — the full list written on CREATE (e.g. `[:Access, :Shelf, :Instance]`)

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
