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
- **Every node is created with at least two labels**: the domain label (PascalCase short name of the Ash domain module) and the module label (PascalCase short name of the resource module). When a resource uses a fragment that declares a `label`, that fragment label is also written on CREATE — so a resource extending `BaseInstance` (which declares `label :Instance`) produces nodes with three labels: `[:Domain, :ResourceName, :Instance]`. When the domain uses `AshNeo4j.DataLayer.Domain` via a domain fragment, an additional domain fragment label is also written. Reads, updates, and deletes match on `[domain_label, module_label]` — always uniquely scoped to the resource type.
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

When `expr:` is used, AshNeo4j fetches full destination node records, casts them to resource structs, evaluates the Ash expression on each in Elixir, and applies the aggregate kind. This supports arbitrary Ash expressions — field access, `get_path` for nested struct navigation, arithmetic, etc.

Note: `expr:` in aggregate declarations is a programmatic API (`Ash.aggregate/3`, `Ash.Query.aggregate/3`). It is not available in the resource-level `aggregates do` DSL block.

## Calculations

AshNeo4j supports **expression calculations** — calculations declared with `expr(...)` in the `calculations` block. They are evaluated in Elixir after records are loaded from Neo4j, so they work with any Ash expression including arithmetic, string concatenation, and references to other attributes.

```elixir
calculations do
  calculate :score_doubled, :integer, expr(score * 2)
  calculate :full_name, :string, expr(first_name <> " " <> last_name)
  calculate :label, :string, expr(title <> " (" <> type <> ")")
end
```

Calculations can be:
- **Loaded** via `Ash.load!(records, [:score_doubled])`
- **Filtered on** via `Ash.Query.filter(score_doubled > 10)` — AshNeo4j loads all matching nodes then evaluates the filter in Elixir
- **Sorted on** via `Ash.Query.sort(score_doubled: :asc)` — sort is applied in Elixir after records are loaded

Calculations on embedded struct fields (`Ash.TypedStruct`, nested types) work the same way — the expression is evaluated against the deserialized struct.

Custom calculation modules (`:calculate` callback) are not currently supported — only expression (`expr(...)`) calculations.

## Spatial types and expressions

AshNeo4j stores geometries using [`ash_geo`](https://hex.pm/packages/ash_geo) types — declare attributes as `AshGeo.GeoJson` with a `geo_types` constraint, carrying [`%Geo.*{}`](https://hex.pm/packages/geo) structs. `st_*` expression functions (`st_contains`, `st_within`, `st_intersects`, `st_distance`, `st_distance_in_meters`, `st_dwithin`, `st_closest_point`) match ash_geo / PostGIS signatures. Predicates push down to Neo4j's native `point.distance` and `point.withinBBox` wherever possible.

```elixir
attributes do
  attribute :location, AshGeo.GeoJson, constraints: [geo_types: [:point], force_srid: 4326]
  attribute :bounds,   AshGeo.GeoJson, constraints: [geo_types: [:polygon], force_srid: 4326]
end

require Ash.Query

# Service qualification: which Places contain the customer point?
Place
|> Ash.Query.filter(st_contains(bounds, ^customer_point))
|> Ash.read!()

# POIs within 5 km
Place
|> Ash.Query.filter(st_dwithin(location, ^customer_point, 5_000))
|> Ash.read!()
```

WGS-84 2D only in this release. On disk, each geometry stores as a canonical RFC 7946 GeoJSON `STRING` at `<attr>.json` plus scalar Point companions for indexed bbox prefilter (`<attr>.bbSW`/`<attr>.bbNE`); Point additionally keeps a native `<attr>.point` for `point.distance` pushdown. **Geometries nested inside TypedStructs / embedded resources get their indexable companion promoted to a node-level property too** — a location buried in a characteristic is still indexable. Storage is **indexable, not yet indexed** — `AshNeo4j.Spatial.create_index(Place, :location)` builds and runs the POINT index Cypher from the resource + attribute (operator-invoked, not automatic). `AshNeo4j.Type.Point` / `AshNeo4j.Type.Box` were removed in 0.8.0 — full migration notes, recursive-promotion details, holiness composition, and limitations in `usage-rules/spatial.md`.

## Combination queries

AshNeo4j supports all five [Ash combination query types](https://hexdocs.pm/ash/combination-queries.html) — `:base`, `:union`, `:union_all`, `:intersect`, `:except`. Combinations of `:union` / `:union_all` push down to a single Cypher `CALL { … UNION/UNION ALL … }` block; combinations involving `:intersect` / `:except` (or mixed union types) are computed in Elixir over `MapSet`s of node ids, then the keep-set is fetched in one final query.

```elixir
require Ash.Query
require Ash.Expr
import Ash.Expr

# Set difference at a common resource — e.g. "customers in some CSA but not in any NSA"
Customer
|> Ash.Query.combination_of([
  Ash.Query.Combination.base(filter: expr(in_csa)),
  Ash.Query.Combination.except(filter: expr(in_nsa))
])
|> Ash.read!()
```

Note: `union` and `union_all` look identical at the Ash record level (records dedup by primary key in `consolidate_groups/1`); the Cypher-level duplicate-preservation is only observable when querying Cypher directly. Full details, polymorphic-resource pattern for cross-subtype combinations, and execution-path notes in `usage-rules/combination-queries.md`.

## Naming conventions

AshNeo4j enforces Neo4j conventions at compile time:

- **Node labels** must be `PascalCase` atoms — e.g. `:Comment`, `:BlogPost`
- **Node property names** must be `camelCase` — e.g. `createdAt`, `firstName`
- **Edge labels** must be `MACRO_CASE` atoms — e.g. `:BELONGS_TO`, `:WRITTEN_BY`
- **Edge direction** must be `:incoming` or `:outgoing` (relative to the source resource)

Ash attribute names use `snake_case` as normal. AshNeo4j automatically translates `snake_case` attributes to `camelCase` node properties. Use the `source:` option on an attribute to override the property name explicitly.

The `id` attribute is a special case: Neo4j reserves `id` for its internal node identity, so AshNeo4j stores it using the camelCase short name of its type instead (e.g. `:uuid` → `uuid` property, `:string` → `string` property, `:integer` → `integer` property).
