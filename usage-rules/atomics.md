<!--
SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Atomic, bulk and optimistic-lock writes (#361, #379)

AshNeo4j renders Ash atomics straight to Cypher — the new value is computed by
the database in a `SET`, not read into Elixir, mutated, and written back. This
removes a read-modify-write round trip and the lost-update race that comes with
it.

## Atomic update

`changeset.atomics` render to a Cypher `SET`. Numeric expressions, string
`concat` / `trim`, and enum/atom forms (via their stored string) are supported.

```elixir
require Ash.Query
import Ash.Expr

post
|> Ash.Changeset.for_update(:update)
|> Ash.Changeset.atomic_update(:score, expr(score + 1))
|> Ash.update!()
```

## Bulk update and destroy

`Ash.bulk_update` / `Ash.bulk_destroy` with `strategy: :atomic` run as a single
`update_query/4` / `destroy_query/4` — one Cypher statement over the matched
set, not N round trips.

```elixir
# bulk atomic update
Post
|> Ash.Query.filter(draft == true)
|> Ash.bulk_update!(:publish, %{}, strategy: :atomic)

# bulk atomic destroy — "delete what matches"; a guard-protected node is
# skipped, not deleted
Specification
|> Ash.bulk_destroy!(:destroy, %{}, strategy: :atomic, return_records?: true)
```

## Optimistic locking — `StaleRecord` on miss

A single **filtered** update or destroy carries its filter into the Cypher as a
guard. If the guard no longer holds (someone else moved the value first), the
write touches nothing and returns `Ash.Error.Changes.StaleRecord` — the lost
update is **observable**, not a silent no-op.

```elixir
# only succeeds while score is still 5; otherwise StaleRecord
post
|> Ash.Changeset.for_update(:update)
|> Ash.Changeset.filter(expr(score == 5))
|> Ash.Changeset.atomic_update(:score, expr(score + 1))
|> Ash.update()
#=> {:error, %Ash.Error.Changes.StaleRecord{}}   # if the guard missed
```

The same guard-on-miss → `StaleRecord` rule applies to guarded relationship
attach/detach (#368), so optimistic locking behaves consistently across the
write path.

## Atomic upsert — `MERGE` (#379)

A create-or-update keyed on an identity renders an atomic Cypher `MERGE`, so
concurrent upserts converge on a single node instead of racing to duplicates.
Pair it with the uniqueness constraint for that identity (see
`usage-rules/identities.md`) for a database-enforced guarantee.

```elixir
Ash.create!(Upsert, %{first_name: "Donald", surname: "Duck", field: "two"},
  upsert?: true, upsert_identity: :full_name)
```
