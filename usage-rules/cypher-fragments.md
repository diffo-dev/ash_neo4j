<!--
SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Cypher fragments — the filter escape hatch

`fragment(...)` lets you drop a snippet of raw Cypher into a **filter**, for a
condition AshNeo4j doesn't push down on its own — for example an APOC function. The
point is to keep that query *inside Ash* (authorization, the resource model,
composability) instead of dropping to raw Cypher for the one condition.

> This is the **expression** `fragment/N` (analogous to `ash_postgres`'s SQL
> fragment), not an Ash **resource** fragment — they share the word only.

```elixir
require Ash.Query

# Fuzzy, typo-tolerant text match with an APOC function
Post
|> Ash.Query.filter(fragment("apoc.text.levenshteinDistance(?, ?) <= ?", title, "John Smith", 2))
|> Ash.read!()
```

## How arguments are rendered

The `?` arguments are bound, never interpolated, so the fragment is injection-safe:

| `?` argument | Renders to |
|---|---|
| an attribute reference (e.g. `title`) | `s.<property>` (the node alias + camelCased property) |
| a literal (number, string, boolean) | a bound `$frag_N` parameter |

The raw text between the `?`s is author-supplied Cypher, written as-is. So
`fragment("apoc.text.levenshteinDistance(?, ?) <= ?", title, "John Smith", 2)` renders
`WHERE (apoc.text.levenshteinDistance(s.title, $frag_0) <= $frag_1)`.

You are responsible for what the server can run — e.g. APOC must be installed for an
`apoc.*` fragment. AshNeo4j renders the call faithfully; it doesn't load or require
APOC. Check from a deploy/start-up healthcheck with
`AshNeo4j.BoltyHelper.apoc_available?/0` (it introspects the server; installing APOC
is the operator's job).

## Scope and limits

- **The fragment must be the whole filter.** A fragment combined with other
  conditions (`fragment(...) and x == 1`) is **refused** with
  `AshNeo4j.Error.UnsupportedFilterFragment` — not silently dropped. Raw Cypher
  can't be re-evaluated in Elixir, so a half-applied fragment would give wrong
  results; refusing is the safe floor. (Combining fragments with other predicates is
  a possible future enhancement.)
- **Arguments must be a plain attribute reference or a literal.** A related field,
  calculation or nested expression is refused.
- Fragments apply to **filters** only (not calculations or sorts, which AshNeo4j
  evaluates in-memory).

## Staying inside the data layer

A fragment carries an *expression* into a filter while the data layer still does the
heavy lifting: it translates the `?` attribute references to the right `s.<property>`,
scopes the read to the resource's labels, and handles types. That translation is the
hard part — AshNeo4j introspects the DSL and maps domains, resources, attributes and
relationships onto labels, nodes, edges and properties, with a lot of nuance — and a
fragment lets you reach raw Cypher *without* giving it up.

For something a fragment genuinely can't express — a `CALL apoc.*` procedure, a
one-off migration — `AshNeo4j.Cypher.run/2` will run arbitrary Cypher on the data
layer's Bolt pool (see `usage-rules/spatial.md`). But that hands *you* everything the
data layer reconciles: the exact labels (domain + resource + any fragment base),
camelCased property names, label scoping and type conversion — plus the Ash,
data-layer, Cypher, transaction, filter and changeset semantics it weaves together.
It's a genuine last resort, not a path we encourage: you'd be reimplementing by hand a
deep, nuanced layer, and it's easy to get subtly wrong. It's there if you need to
descend — just come equipped for everything down there.
