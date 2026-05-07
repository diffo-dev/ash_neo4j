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
- **Every node is created with two labels**: the domain label (PascalCase short name of the Ash domain module) and the resource label. Only the resource label is used when reading, updating, or destroying. The domain label cannot be overridden.
- **Transactions are supported.** A test sandbox (`AshNeo4j.Sandbox`) provides per-test transaction isolation — see `usage-rules/testing.md`.

## Naming conventions

AshNeo4j enforces Neo4j conventions at compile time:

- **Node labels** must be `PascalCase` atoms — e.g. `:Comment`, `:BlogPost`
- **Node property names** must be `camelCase` — e.g. `createdAt`, `firstName`
- **Edge labels** must be `MACRO_CASE` atoms — e.g. `:BELONGS_TO`, `:WRITTEN_BY`
- **Edge direction** must be `:incoming` or `:outgoing` (relative to the source resource)

Ash attribute names use `snake_case` as normal. AshNeo4j automatically translates `snake_case` attributes to `camelCase` node properties. Use the `source:` option on an attribute to override the property name explicitly.

The `id` attribute is a special case: Neo4j reserves `id` for its internal node identity, so AshNeo4j stores it using the camelCase short name of its type instead (e.g. `:uuid` → `uuid` property, `:string` → `string` property, `:integer` → `integer` property).
