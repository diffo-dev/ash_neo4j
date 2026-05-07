<!--
SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Relationships

## Relationships are graph edges, not columns

In AshNeo4j, relationships are stored as edges in the graph — not as foreign key columns on nodes. This has important consequences:

- **Do not add foreign key attributes** to a resource to model a relationship. There are no `_id` columns.
- **Many-to-many requires a joiner node resource** — see the many-to-many section below. AshNeo4j does not use edge properties.
- An Ash `belongs_to` relationship does not create a foreign key attribute on the resource. The relationship is expressed entirely through a graph edge.

## Defining relationships

Define Ash relationships in the `relationships` block as normal, then declare the corresponding graph edge in `relate`:

```elixir
# Post resource
relationships do
  has_many :comments, MyApp.Blog.Comment
end

neo4j do
  relate [{:comments, :HAS_COMMENT, :outgoing, :Comment}]
end

# Comment resource
relationships do
  belongs_to :post, MyApp.Blog.Post, define_attribute?: false
end

neo4j do
  relate [{:post, :HAS_COMMENT, :incoming, :Post}]
end
```

Note `define_attribute?: false` on the `belongs_to` — there is no foreign key attribute to define.

## Edge direction

Direction is always described from the perspective of the source resource's node:

- `:outgoing` — the edge points away from this node: `(this)-[:EDGE]->(other)`
- `:incoming` — the edge points toward this node: `(other)-[:EDGE]->(this)`

Both sides of a relationship refer to the same physical edge in the graph, just from opposite directions. The `edge_label` must match on both sides.

## Many-to-many

AshNeo4j does not use edge properties. Many-to-many relationships are modelled
using a **joiner resource** — a dedicated node that sits between the two sides.
The pattern is two back-to-back relationships: many-to-one into the joiner, and
one-to-many out of it.

The joiner resource has two `belongs_to` relationships sharing the same edge
label: one `:incoming` (from the source) and one `:outgoing` (to the target).

```elixir
# PostTag joiner resource
relationships do
  belongs_to :post, MyApp.Blog.Post, define_attribute?: false
  belongs_to :tag, MyApp.Blog.Tag, define_attribute?: false
end

neo4j do
  relate [
    {:post, :TAGGED_WITH, :incoming, :Post},
    {:tag, :TAGGED_WITH, :outgoing, :Tag}
  ]
end

# Post resource
relationships do
  has_many :post_tags, MyApp.Blog.PostTag
end

# Tag resource
relationships do
  has_many :post_tags, MyApp.Blog.PostTag
end
```

The joiner node is a first-class resource: it can carry its own attributes and
be further enriched by relationships to other nodes. This is the preferred way
to model metadata that would otherwise require edge properties.

## Avoiding dense nodes

A node that accumulates a very high number of edges (thousands or more) becomes a **dense node**. Traversals through it degrade significantly — unlike SQL where you add an index, in Neo4j you need to reconsider the graph topology at modelling time.

The most effective mitigation is to **omit `relate` on the high-cardinality side**. If you only need to traverse in one direction, only declare it in one direction. The reverse edge still exists in the graph and can be protected with `guard` — you just cannot accidentally load it via Ash.

```elixir
# Instance resource — traversal TO Specification makes sense
neo4j do
  relate [{:specification, :SPECIFIED_BY, :outgoing, :Specification}]
end

# Specification resource — NO relate back to Instance
# A Specification could be referenced by thousands of instances.
# Omitting relate prevents any action from loading them all.
# guard still protects the Specification from deletion while instances reference it.
neo4j do
  guard [{:SPECIFIED_BY, :incoming, :Instance}]
end
```

Apply this pattern whenever a `has_many` relationship could grow without bound. Be deliberate about which direction of traversal your application actually needs.

## Default relate behaviour

If you omit `relate` entries, AshNeo4j generates defaults:

- Direction is always `:outgoing`
- Edge label is derived from the Ash relationship type

Provide explicit `relate` entries when the direction or label needs to be different, or when two relationships between the same pair of labels would otherwise be ambiguous.

## has_one

`has_one` is supported but of limited utility. It works like `has_many` except AshNeo4j returns a single record (or `nil`) instead of a list. It does not enforce uniqueness in the graph — if multiple edges match, one record is returned arbitrarily.

The only case where it adds value over `has_many` is when you want to surface a single designated record as a named field on the struct — for example, the most recently fired event on an instance — without exposing the full collection:

```elixir
has_one :event, MyApp.Provider.Event do
  description "the most recently fired event"
  public? true
  destination_attribute :instance_id
end
```

Declare the `relate` entry the same way you would for `has_many`. No additional DSL is needed.

If you actually need "the most recent" semantics, sort within the query at call time — `has_one` itself does not order results.

## Uniqueness constraint

The combination `{edge_label, edge_direction, destination_label}` must be unique per resource. AshNeo4j uses this triple to look up the correct Ash relationship when traversing an edge. Duplicate triples will be rejected at compile time.
