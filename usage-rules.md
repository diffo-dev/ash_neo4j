<!--
SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Rules for working with AshNeo4j

## What AshNeo4j is

AshNeo4j is an `Ash.DataLayer` that stores resources as nodes in a Neo4j graph database. Use it when your domain is naturally graph-shaped — highly connected data, variable-depth traversals, or where relationships are first-class.

Configure it on a resource:

```elixir
use Ash.Resource,
  domain: MyApp.Blog,
  data_layer: AshNeo4j.DataLayer
```

## Key differences from AshPostgres / Ecto

Do not carry SQL assumptions into AshNeo4j. The differences are fundamental:

| Concept | AshPostgres / Ecto | AshNeo4j |
|---|---|---|
| Storage unit | Table row | Graph node |
| Schema | SQL table + migrations | No migrations — nodes are schema-free |
| Relationships | Foreign key columns | Graph edges — no columns on the resource |
| Many-to-many | JOIN table resource | Joiner node resource (no edge properties) |
| Config | `Ecto.Repo` | `Bolty` named process (`Bolt`) |
| DSL block | `postgres do ... end` | `neo4j do ... end` |
| Repo module | `MyApp.Repo` | Not used — Bolty is global |
| Migrations | `mix ash_postgres.generate_migrations` | None |

- **Never add foreign key attributes** to an AshNeo4j resource for the purpose of expressing a relationship. Relationships are graph edges managed by the `relate` DSL and the Ash `relationships` block.
- **Many-to-many requires a joiner resource** — a dedicated node with two `belongs_to` relationships. AshNeo4j does not use edge properties. Do not attempt a direct many-to-many edge.
- There is no `Ecto.Repo`. The Neo4j connection pool is a Bolty named process (`Bolt`), configured in `runtime.exs` and added to your supervision tree.
- **Every node is created with at least two labels**: the domain label (PascalCase short name of the Ash domain module) and the resource label. When a resource uses a fragment that declares a `label`, that fragment label is also written on create — so a resource extending `BaseInstance` (which declares `label :Instance`) will produce nodes with three labels: `[:Domain, :ResourceName, :Instance]`. Only the resource label is used when reading, updating, or destroying. The domain label cannot be overridden.
- **Transactions are supported.** A test sandbox (`AshNeo4j.Sandbox`) provides per-test transaction isolation — see `usage-rules/testing.md`.
- **Aggregates are supported** for kinds `:count`, `:exists`, `:sum`, `:avg`, `:min`, `:max`, `:first`, `:list`. The `:custom` kind is not supported. Fields stored as JSON (embedded resources, `Ash.TypedStruct`, `Ash.Type.NewType`, `Ash.Type.Map`, etc.) are also aggregatable — see the Aggregates section below.

## Aggregates

AshNeo4j supports the standard Ash aggregate kinds: `:count`, `:exists`, `:sum`, `:avg`, `:min`, `:max`, `:first`, `:list`. The `:custom` kind is not supported.

Declare aggregates in the standard Ash `aggregates` block — no AshNeo4j-specific DSL is required:

```elixir
aggregates do
  count :comment_count, :comments
  exists :has_comments, :comments
  sum :total_score, :comments, field: :score
  list :comment_titles, :comments, field: :title
end
```

Aggregates are executed as Cypher `OPTIONAL MATCH` traversals from the source node through the relationship path. Both single-hop and multi-hop paths are supported — AshNeo4j resolves each hop via the resource mapping and builds the full chain in a single query.

Aggregates are available both standalone (`Ash.aggregate/3`) and when loading on records (`Ash.load/2`).

### Flat property fields

For scalar fields (`:string`, `:integer`, `:boolean`, etc.) the aggregation is fully pushed down to Cypher — `COUNT`, `SUM`, `AVG`, `MIN`, `MAX`, `collect()` all run in the database.

### Embedded struct and JSON-type fields

When `field:` points to an attribute whose type is stored as JSON — `Ash.TypedStruct`, `Ash.Type.NewType` with a map storage type, embedded resources, `Ash.Type.Map`, `Ash.Type.Union`, etc. — AshNeo4j automatically switches to a two-phase strategy:

1. **Cypher** `collect(d.prop)` gathers the raw JSON strings from Neo4j.
2. **Elixir** deserializes each value using `AshNeo4j.DataLayer.Cast` (which calls `Ash.Type.cast_stored/3`), then applies the aggregate kind in memory.

This means you can declare `:list` and `:first` aggregates directly on typed struct fields and get back fully deserialized structs:

```elixir
# On the destination resource
attribute :metadata, MyApp.MetadataStruct, public?: true

# On the source resource
aggregates do
  list :all_metadata, :related_things, field: :metadata
  first :first_metadata, :related_things, field: :metadata
end
```

For `:sum`, `:avg`, `:min`, `:max` the deserialized values must be directly comparable/numeric — if you need to aggregate a sub-field within a struct, use an expression aggregate (see below).

Aggregating over a calculation result is not supported — the field must be a stored attribute.

### Expression aggregates (no elevation needed)

For aggregating over a sub-field of an embedded struct or any Ash expression, use the programmatic aggregate API with `expr:`:

```elixir
# Sum the age field within a DogTypedStruct stored on each Comment
Ash.aggregate(Post, {:total_dog_age, :sum, [
  path: [:comments],
  expr: Ash.Expr.expr(get_path(dog, [:age])),
  expr_type: :integer
]})
```

When `expr:` is used, AshNeo4j fetches full destination node records, casts them to resource structs, evaluates the Ash expression on each via `Ash.Expr.eval_hydrated/2`, and applies the aggregate kind in Elixir. This supports arbitrary Ash expressions — field access, `get_path` for nested struct navigation, arithmetic, etc.

Note: `expr:` in aggregate declarations is a programmatic API (`Ash.aggregate/3`, `Ash.Query.aggregate/3`). It is not available in the resource-level `aggregates do` DSL block.

## Naming conventions

AshNeo4j enforces Neo4j conventions at compile time:

- **Node labels** must be `PascalCase` atoms — e.g. `:Comment`, `:BlogPost`
- **Node property names** must be `camelCase` — e.g. `createdAt`, `firstName`
- **Edge labels** must be `MACRO_CASE` atoms — e.g. `:BELONGS_TO`, `:WRITTEN_BY`
- **Edge direction** must be `:incoming` or `:outgoing` (relative to the source resource)

Ash attribute names use `snake_case` as normal. AshNeo4j automatically translates `snake_case` attributes to `camelCase` node properties. Use the `source:` option on an attribute to override the property name explicitly.

The `id` attribute is a special case: Neo4j reserves `id` for its internal node identity, so AshNeo4j stores it using the camelCase short name of its type instead (e.g. `:uuid` → `uuid` property, `:string` → `string` property, `:integer` → `integer` property).
