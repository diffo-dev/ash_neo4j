<!--
SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Vector embeddings and similarity search

AshNeo4j stores vector embeddings with the `AshNeo4j.Types.Vector` attribute type and ranks/filters them with the `vector_similarity` and `vector_cosine_distance` expression functions. Both push down to Neo4j's `vector.similarity.cosine/2`, falling back to an exact in-memory evaluation otherwise.

> **Cypher 25 is the requirement — not Bolt 6.0.** Embeddings are stored and queried as `LIST<FLOAT>`, which is what `vector.similarity.cosine/2` operates on, so similarity search works on any Neo4j ≥ 2025.06 server over Bolt 5.8. The native Bolt 6.0 `%Bolty.Types.Vector{}` type is a query-parameter wire type that **cannot be written as a node property**, so AshNeo4j never uses it for storage.

## Declaring a vector attribute

```elixir
attributes do
  attribute :embedding, AshNeo4j.Types.Vector,
    public?: true,
    constraints: [element_type: :float32, dimensions: 1536]
end
```

| Constraint | Values | Meaning |
|---|---|---|
| `:element_type` | `:float32` (default), `:float64` | Element precision. Carried into the vector index config; storage is always a Neo4j float list. |
| `:dimensions` | positive integer | Expected vector length. Validated on cast (a wrong-length vector is rejected) and used by `AshNeo4j.Vector.create_index/3`. |

The Elixir-side value is a plain `[float()]` list:

```elixir
note = Note |> Ash.create!(%{body: "…", embedding: [0.12, -0.04, 0.98, ...]})
note.embedding  #=> [0.12, -0.04, 0.98, ...]
```

`cast_input/2` and `cast_stored/2` also accept a `%Bolty.Types.Vector{}` defensively and unwrap it to `[float()]`, but Neo4j never returns one (it can't store one), so reads are always plain lists.

> The built-in `Ash.Type.Vector` is a different module and is **not** supported by AshNeo4j — use `AshNeo4j.Types.Vector`.

## On-disk shape

The embedding is stored as a single `LIST<FLOAT>` node property at the attribute's translated (camelCase) property name — no companions, no JSON wrapping:

```
embedding = [0.12, -0.04, 0.98, ...]   (Neo4j LIST<FLOAT>)
```

This is exactly the shape Neo4j's vector index and `vector.similarity.cosine/2` expect.

## Expression functions

| Function | Returns | Scale | Order |
|---|---|---|---|
| `vector_similarity(attr, ^q)` | float — Neo4j-normalised cosine similarity | `[0.0, 1.0]` (`1.0` identical, `0.5` orthogonal, `0.0` opposite) | higher = closer |
| `vector_cosine_distance(attr, ^q)` | float — pgvector-style cosine distance | `[0.0, 2.0]` (`0.0` identical, `2.0` opposite) | lower = closer |

Neo4j's `vector.similarity.cosine/2` returns a **normalised** similarity `(1 + raw_cosine) / 2` in `[0, 1]` — not the raw `[-1, 1]` cosine. `vector_similarity` exposes that value directly; `vector_cosine_distance` rescales it to pgvector's `<=>` semantics as `2 * (1 - similarity)` (which equals `1 - raw_cosine`).

```elixir
require Ash.Query
import Ash.Expr

q = embed("a natural-language query")   # your embedding model → [float()]

# rank by relevance, ash_ai-style (distance: ascending, closest first)
Note
|> Ash.Query.filter(vector_cosine_distance(embedding, ^q) < 0.5)
|> Ash.Query.sort({calc(vector_cosine_distance(embedding, ^q), type: :float), :asc})
|> Ash.Query.limit(10)
|> Ash.read!()

# or with similarity (descending, closest first)
Note
|> Ash.Query.sort({calc(vector_similarity(embedding, ^q), type: :float), :desc})
|> Ash.Query.limit(10)
|> Ash.read!()
```

Both functions push down to Cypher:

```cypher
-- vector_similarity(embedding, $q)
vector.similarity.cosine(s.embedding, $q)

-- vector_cosine_distance(embedding, $q)
(2.0 * (1.0 - vector.similarity.cosine(s.embedding, $q)))
```

in both `WHERE` (filter) and `ORDER BY` (sort). The query embedding is bound as a plain `LIST<FLOAT>` parameter.

### Pushdown agrees with in-memory evaluation

The data layer always re-applies a query's filter in Elixir (`Ash.Filter.Runtime`) after the Cypher read, treating the pushdown as an over-selecting prefilter. So `evaluate/1` for both functions computes the **same** value the Cypher does — mirroring Neo4j's `(1 + raw_cosine)/2` normalisation exactly (`AshNeo4j.Functions.VectorMath`). This also means the functions work correctly even with no pushdown (pure in-memory), and a `nil` or wrong-shaped embedding evaluates to `nil` (excluded).

### ash_ai interop

`vector_cosine_distance` deliberately mirrors the name and semantics of AshPostgres/pgvector's `vector_cosine_distance` (`<=>`), so the same `read` action expression composes across data layers:

```elixir
read :search do
  argument :query, :string, allow_nil?: false

  prepare before_action(fn query, _ctx ->
    {:ok, [v]} = MyApp.Embeddings.generate([query.arguments.query], [])

    query
    |> Ash.Query.filter(vector_cosine_distance(embedding, ^v) < 0.5)
    |> Ash.Query.sort({calc(vector_cosine_distance(embedding, ^v), type: :float), :asc})
    |> Ash.Query.limit(10)
  end)
end
```

## Indexes — indexable, not yet indexed in queries

`AshNeo4j.Vector` builds and runs the `CREATE VECTOR INDEX` Cypher from a resource + attribute, so you don't hand-encode the label, translated property name, dimensions, and similarity function:

```elixir
# Create the HNSW vector index for a vector attribute
AshNeo4j.Vector.create_index(Note, :embedding)

# Euclidean distance instead of the default cosine
AshNeo4j.Vector.create_index(Note, :embedding, similarity_function: :euclidean)

# Rebuild after a dimensions / similarity-function change (DROP IF EXISTS + CREATE)
AshNeo4j.Vector.create_index(Note, :embedding, recreate: true)

# Symmetric remove
AshNeo4j.Vector.drop_index(Note, :embedding)

# Dry run — the CREATE Cypher without touching the database
AshNeo4j.Vector.index_statements(Note, :embedding)
#=> {:ok, "CREATE VECTOR INDEX note_embedding_vector IF NOT EXISTS " <>
#=>       "FOR (n:Note) ON (n.embedding) " <>
#=>       "OPTIONS {indexConfig: {`vector.dimensions`: 1536, `vector.similarity_function`: 'cosine'}}"}
```

`create_index/3` uses `IF NOT EXISTS`, so it's safe to call repeatedly (e.g. from a start-up task). The `:dimensions` constraint is required on the attribute — the index needs the vector size. Consistent with AshNeo4j's no-migrations stance, index lifecycle is a deliberate operator concern; AshNeo4j just doesn't do it *for* you.

> **The index does not yet accelerate queries.** Unlike pgvector — where `ORDER BY embedding <=> $q LIMIT k` transparently uses the HNSW index — Neo4j does **not** consult the vector index for `vector.similarity.cosine` in a `WHERE`/`ORDER BY`. The current pushdown is correct but a **full scan**: every node reached by the `MATCH` is scored. The HNSW index is only consulted by `db.index.vector.queryNodes` / the Cypher 25 `SEARCH` clause, which replace the `MATCH` entirely — tracked as indexed-KNN follow-up [#297](https://github.com/diffo-dev/ash_neo4j/issues/297). Create the index now (so it's ready and populated); query acceleration lands with #297.

## Testing against a Cypher 25 server

The default test pool (`Bolt`) targets a pre-2025.06 server, so vector tests need a Cypher-25-capable pool. AshNeo4j's test suite configures a second `Bolt6` pool (Neo4j 2026.05) and routes to it per-process:

```elixir
use ExUnit.Case, async: false   # the pool is small and the sandbox holds a connection

@describetag :cypher25          # excluded from the default run

setup do
  Process.put(:ash_neo4j_pool, Bolt6)   # route this process's queries + capability checks
  AshNeo4j.Sandbox.checkout()
  on_exit(&AshNeo4j.Sandbox.rollback/0)
end
```

`AshNeo4j.BoltyHelper.with_pool/2` wraps the override for code that runs in a separate process (e.g. an `on_exit` cleanup). Cosine similarity is a plain Cypher function and needs no index, so search tests run inside the sandbox transaction. See `usage-rules/testing.md` for the pool-routing details.

## Limitations

- **Queries are a full scan** — the vector index is not yet used for `vector.similarity.cosine`. Fine for modest vector counts; indexed top-K is [#297](https://github.com/diffo-dev/ash_neo4j/issues/297).
- **No native `db.index.vector.queryNodes` / `SEARCH` primitive yet** — there is no `vector_near(attr, ^q, top_k: n)`; ranking is expressed as `sort + limit` over the cosine expression (#297).
- **Cosine only at the expression level** — `vector_similarity` / `vector_cosine_distance` are cosine; euclidean is available at the *index* level (`similarity_function: :euclidean`) but not yet as an expression function.
- **Storage is `LIST<FLOAT>`** — the native Bolt 6.0 VECTOR type cannot be persisted as a node property, by design here.
- **Index lifecycle is the operator's responsibility** (no migrations).
