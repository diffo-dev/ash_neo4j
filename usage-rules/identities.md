<!--
SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Primary keys, identities and uniqueness constraints

An Ash `identity` declares that a set of attributes is unique. AshNeo4j enforces
that at the database level with a Neo4j uniqueness constraint, so concurrent writes
can't create duplicates and you don't need `pre_check?` (an Elixir-side read that
still leaves a race window). The resource's **primary key** gets a constraint too,
enforcing primary-key uniqueness among nodes of the resource's label.

```elixir
identities do
  identity :unique_assignment, [:source_id, :pool, :thing, :value]
end
```

## Creating the constraints

Like vector indexes, this is an ergonomic helper you run yourself (e.g. from a
start-up or release task) — AshNeo4j does not run migrations on boot. Statements use
`IF NOT EXISTS`, so they are safe to run repeatedly.

```elixir
# Create the uniqueness constraint(s) for every identity on a resource
AshNeo4j.Constraint.create_constraints(AssignmentRelationship)

# Review the Cypher without touching the database
AshNeo4j.Constraint.constraint_statements(AssignmentRelationship)
#=> {:ok, ["CREATE CONSTRAINT assignmentrelationship_unique_assignment IF NOT EXISTS " <>
#          "FOR (n:AssignmentRelationship) REQUIRE (n.sourceId, n.pool, n.thing, n.value) IS UNIQUE"]}

# Drop them
AshNeo4j.Constraint.drop_constraints(AssignmentRelationship)
```

This creates the **primary-key** constraint (`<label_lower>_pk`) and one per
identity (`<label_lower>_<identity_name>`). Single- and multi-attribute keys are
both supported (composite `IS UNIQUE` constraints work on Neo4j Community Edition).
The primary-key constraint is skipped when an identity already constrains the same
attributes (e.g. a natural composite primary key that's also declared an identity).

## Conflicts are surfaced in Ash terms

When a create violates a constraint, AshNeo4j returns Ash's own identity-conflict
error — an `Ash.Error.Changes.InvalidAttribute` ("has already been taken") on each
attribute of the identity — not a raw Neo4j error. So forms and changesets handle it
exactly as they would on any other data layer.

```elixir
{:error, error} = AssignmentRelationship |> Ash.create(%{source_id: 1, pool: :p, thing: :t, value: 7})
# => InvalidAttribute on :source_id/:pool/:thing/:value, message "has already been taken"
```

## What can't be enforced (refused, not silently skipped)

Two Ash identity options have no Neo4j uniqueness-constraint equivalent. Rather than
create nothing and silently leave the identity unenforced — which would permit the
duplicates the constraint exists to prevent — AshNeo4j **refuses** them:

| Identity option | Why | When you find out |
|---|---|---|
| `nils_distinct?: false` | Neo4j treats `nil`s as distinct and can't be made to treat them as equal | compile time (`AshNeo4j.Verifiers.VerifyIdentities`) and from `AshNeo4j.Constraint` (`AshNeo4j.Error.UnsupportedIdentity`) |
| a filtered identity (`where:`) | Neo4j has no partial/filtered constraint | same |

Drop the unsupported option, or enforce that identity another way — it will not fall
back to a database constraint.

The default `nils_distinct?: true` maps cleanly: a node missing any of the
constrained attributes is not subject to the constraint (its `nil`s are distinct).

## Atomic upsert

An `upsert?: true` create keyed on an identity is a single, race-free `MERGE`:

```cypher
MERGE (n:Label {<identity properties>})
ON CREATE SET n += {<the rest of the node>}
ON MATCH  SET n += {<set_on_upsert fields>}
RETURN n
```

— no read-then-write round-trip and no race window (the identity's uniqueness
constraint backs it). This is plain Cypher, so it works on any supported server.
Upserts that also carry `changeset.atomics`, managed relationships, or an upsert
condition fall back to the read-then-write path.
