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

### Two labels per node

Every node is created with **two** labels: the domain label and the resource label. The domain label is the PascalCase short name of the Ash domain module (e.g. `MyApp.Blog` → `:Blog`). It is applied automatically — you do not declare it.

On **read, update, and destroy**, only the resource label is used to match nodes. The domain label is a namespace marker visible in Neo4j but not used for query routing. The domain label is always derived from the domain module name and cannot be overridden.

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
