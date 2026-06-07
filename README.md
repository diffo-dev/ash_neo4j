<!-- 
SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# AshNeo4j

[![Module Version](https://img.shields.io/hexpm/v/ash_neo4j)](https://hex.pm/packages/ash_neo4j)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen)](https://hexdocs.pm/ash_neo4j/)
[![License](https://img.shields.io/hexpm/l/ash_neo4j)](https://github.com/diffo-dev/ash_neo4j/blob/master/LICENSES/MIT.md)
[![REUSE status](https://api.reuse.software/badge/github.com/diffo-dev/ash_neo4j)](https://api.reuse.software/info/github.com/diffo-dev/ash_neo4j)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/diffo-dev/ash_neo4j)

Ash DataLayer for Neo4j, configurable using a simple DSL

## Installation

### With Igniter (recommended)

```bash
mix igniter.install ash_neo4j
```

This automatically configures the formatter, adds Bolty connection config to `config/runtime.exs`, and wires Bolty into your supervision tree.

### Manual

Add to deps in `mix.exs`:

```elixir
def deps do
  [
    {:ash_neo4j, "~> 0.4"},
  ]
end
```

Then follow the [Bolty configuration](#installing-neo4j-and-configuring-bolty) steps below.

## AI Coding Assistants

AshNeo4j ships usage rules for AI coding assistants. If your project uses
[`usage_rules`](https://hex.pm/packages/usage_rules), add `ash_neo4j` to your
`:usage_rules` config and run `mix usage_rules.sync` to merge the rules into
your `AGENTS.md` (or `CLAUDE.md`).

## Tutorial

To get started you need a running instance of [Livebook](https://livebook.dev/)

[![Run in Livebook](https://livebook.dev/badge/v1/blue.svg)](https://livebook.dev/run?url=https%3A%2F%2Fgithub.com%2Fdiffo%2Ddev%2Fash%5Fneo4j%2Fblob%2Fdev%2Fash%5Fneo4j%5Fdatalayer.livemd)


## Usage

Configure `AshNeo4j.DataLayer` as `data_layer:` within `use Ash.Resource` options:

```elixir
  use Ash.Resource,
    data_layer: AshNeo4j.DataLayer
```

### Configuration

Each Ash.Resource allows configuration of its AshNeo4j.DataLayer. An example Comment resource is given below, it can belong to a Post resource. The neo4j configuration block below is actually unnecessary as written.

```elixir
defmodule Blog.Comment do
  use Ash.Resource,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    label :Comment
    relate [{:post, :BELONGS_TO, :outgoing, :Post}]
  end

  actions do
    default_accept :*
    defaults [:create, :read, :update, :destroy]
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :date_created, :date, source: :dateCreated
  end

  relationships do
    belongs_to :post, Post, public?: true
  end
end
```

## Label

The DSL may be used to label the Ash Resource's underlying graph node. If omitted the Ash Resource's short module name will be used.

```elixir
  neo4j do
    label :Comment
  end
```

## Relate

The DSL may be used to specifically direct any relationship, in the form {relationship_name, edge_label, edge_direction, destination_label}. An entry can be provided for any relationship to override the default values created by AshNeo4j.

```elixir
  neo4j do
    relate [{:post, :BELONGS_TO, :outgoing, :Post}]
  end
```

Default relate clauses are always :outgoing from the source resource, and the edge_label is derived from the Ash relationship type.
Relate clauses, whether specific or default must be unique {_, edge_label, edge_direction, destination_label} for a given source_label to allow determination of the source relationship.

## Guard

The DSL may be used to guard destroy actions, in the form {edge_label, edge_direction, destination_label}. By default incoming allow_nil? false belongs_to are guarded against deletion while relationships exist. Guards can be created independently of explicit relationships.
```elixir
  neo4j do
    guard [{:WRITTEN_BY, :outgoing, :Post}]
  end
```

Guard is useful where the resource has no explicit relationships, but other resources expect the resource to exist while they are related.
Guard can also be used where the underlying node has other edges which should prevent resource destruction.

## Skip

The DSL may be used to skip storing attributes as node properties. This can be useful for 'transient' attributes, or attributes you want to default using the resource but not store explicitly.

```elixir
  neo4j do
    skip [:other_id]
  end
```

## Translate

Translation of resource attributes to/from Neo4j node properties is done without explicit Ash Neo4j DSL.

For convenience Ash Neo4j translates attributes with underscores to camelCase Neo4j properties. Neo4j uses the node property 'id' internally, so Ash Neo4j will translate the 'id' attribute using the camelCased short name of the type, e.g. an 'id' attribute of :uuid type is translated to the 'uuid' node property.

Ash Neo4j also supports the source field in Ash.Resource.Attribute DSL - if present this will be used for the node property. 

## Verifiers

The DSL is verified against misconfiguration and violation of accepted neo4j conventions providing compile time errors:

* neo4j labels must be PascalCase
* neo4j property names must be camelCase
* edge label must be MACRO_CASE
* edge direction must be in [:incoming, :outgoing]
* relate: relationship_name must match the name of a relationship
* relate: relationship enrichment not possible, edge_label, edge_direction and destination_label must be unique
* attribute type requires unsupported term

## Testing

`AshNeo4j.Sandbox` provides test isolation analogous to `Ecto.Adapters.SQL.Sandbox`. Each test that calls `checkout/0` gets a dedicated Neo4j connection with an open transaction. All queries from that test run inside the transaction, which is rolled back automatically when the test process exits. Nothing is ever committed, so there is no data to clean up and tests can safely run in parallel.

### Setup

Replace any `Neo4jHelper.delete_all()` or `Neo4jHelper.delete_nodes/1` teardown with a sandbox checkout:

```elixir
setup_all do
  AshNeo4j.BoltyHelper.start()
end

setup do
  AshNeo4j.Sandbox.checkout()
  on_exit(&AshNeo4j.Sandbox.rollback/0)
end
```

The `on_exit` call is optional — the transaction is rolled back automatically when the test process exits — but is recommended for clarity.

### Parallel tests

Because each test's writes are confined to an uncommitted transaction, tests can run concurrently without interfering:

```elixir
use ExUnit.Case, async: true

setup do
  AshNeo4j.Sandbox.checkout()
  on_exit(&AshNeo4j.Sandbox.rollback/0)
end
```

### Targeting a second Neo4j (pool routing)

The data layer talks to a configurable Bolty pool — `AshNeo4j.BoltyHelper.current_pool/0`, defaulting to `Bolt`. Override it per-process with `with_pool/2` (or `Process.put(:ash_neo4j_pool, Pool)`) to route a test's queries — and the `cypher25?/1` / `policy/1` capability checks — to a different server. AshNeo4j's own suite uses this to run Cypher-25 vector tests against a Neo4j 2026.05 pool (`Bolt6`) while the rest of the suite stays on a 5.x pool; those tests are tagged `:cypher25` and excluded by default. Start a long-lived pool from `test_helper.exs` (not a per-test `setup`) — `Bolty.start_link/1` links the pool to the calling process, so starting it inside a test ties the pool's lifetime to that one test. See `usage-rules/vectors.md`.

## Installing Neo4j and Configuring Bolty

ash_neo4j uses [neo4j](https://github.com/neo4j/neo4j) which must be installed and running.

ash_neo4j uses [bolty](https://github./com/diffo-dev/bolty), a reluctant fork of [boltx](https://github.com/sagastume/boltx)

Your Ash application needs to configure, start and supervise bolty see [bolty documentation](https://hexdocs.pm/bolty/). Make sure to configure any required authorisation.

Tested against Neo4j 5.26.x community (Bolt 5.x) and the calendar-versioned Neo4j 2026.05 community (Bolt 6.0), as well as [DozerDB](https://dozerdb.org) 5.26.x with multi-database. bolty `~> 0.1.0` negotiates Bolt 5.6–6.0 and drops the older Bolt 1–4.x protocols; Neo4j 4.x / Bolt 4.x are not supported.

## Cypher 25 and Cypher 5

Neo4j 2025.06 introduced **versioned Cypher**: the long-standing language is now **Cypher 5** (the default on Neo4j 5.x and on 2025.x servers), and **Cypher 25** is the new calendar-versioned language available from Neo4j 2025.06 onward. The two coexist on a 2025.06+ server and are selected per-query with a leading `CYPHER 5` / `CYPHER 25` clause.

AshNeo4j detects the connected server version (from `Bolty.connection_info/1`'s `server_version`) and, on **Neo4j ≥ 2025.06**, automatically prepends `CYPHER 25 ` to every query so it runs against the Cypher 25 language. On older servers no prefix is emitted and queries run against the server default (Cypher 5). The result is cached per pool; `AshNeo4j.BoltyHelper.cypher25?/0` reports it.

This is distinct from the **Bolt protocol** version (5.6–6.0) — the Bolt version is how the driver talks to the server, while Cypher 5 / 25 is the query language version. Some features require Cypher 25 regardless of Bolt version: for example vector similarity search (see `usage-rules/vectors.md`) needs Neo4j ≥ 2025.06 but works over Bolt 5.8. A feature that requires it calls `AshNeo4j.Cypher.require_cypher25!/0`, which raises `AshNeo4j.Error.RequiresCypher25` on an older server.

> Until [bolty#47](https://github.com/diffo-dev/bolty/issues/47) adds a `cypher25` indicator to `Bolty.Policy`, AshNeo4j derives this from the `server_version` string (`"Neo4j/YYYY.MM.*"` ≥ `2025.06`).

## Elixir, Ash and Neo4j Types

We've made some decisions around how Ash/Elixir types are used to persist attributes as Neo4j properties. Where possible we've used Ash.Type.dump_to_native/cast_stored and 'native' Neo4j types, in many cases encoding to ISO8601, JSON or Base64 strings.


| Ash Type shortname   | Ash Type Module                      | Elixir Type Module | Attribute Value Example                                 | Neo4j Node Property Value Cypher Example               | Cypher Type    |
|----------------------|--------------------------------------|--------------------|---------------------------------------------------------|--------------------------------------------------------|----------------|
| :atom                | Ash.Type.Atom                        | Atom               | :a                                                      | "a"                                                    | STRING         |
| :binary              | Ash.Type.Binary                      | BitString          | <<1, 2, 3>>                                             | "AQID"                                                 | STRING         |
| :boolean             | Ash.Type.Boolean                     | Boolean            | true                                                    | true                                                   | BOOLEAN        |
| :ci_string           | Ash.Type.CiString                    | Ash.CiString       | Ash.CiString.new("Hello")                               | "Hello"                                                | STRING         |
| :date                | Ash.Type.Date                        | Date               | ~D[2025-05-11]                                          | 2025-05-11                                             | DATE           |
| :datetime            | Ash.Type.DateTime                    | DateTime           | ~U[2025-05-11 07:45:41Z]                                | 2025-05-11T07:45:41Z                                   | DATETIME       |
| :decimal             | Ash.Type.Decimal                     | Decimal            | Decimal.new("4.2")                                      | "\"4.2\""                                              | STRING         |
| :duration            | Ash.Type.Duration                    | Duration           | %Duration{month: 2}                                     | PT2H                                                   | DURATION       |
| :duration_name       | Ash.Type.DurationName                | Atom               | :day                                                    | "day"                                                  | STRING         |
| :integer             | Ash.Type.Integer                     | Integer            | 1                                                       | 1                                                      | INTEGER        |
| :float               | Ash.Type.Float                       | Float              | 1.23456789                                              | 1.23456789                                             | FLOAT          |
| :function            | Ash.Type.Function                    | Function           | &AshNeo4j.Neo4jHelper.create_node/2                     | "&AshNeo4j.Neo4jHelper.create_node/2"                  | STRING         |
| subtype_of: :keyword | DogKeyword using Ash.Type.NewType    | DogKeyword         | [name: "Henry", age: 8, breed: :groodle]                | "{\"age\":8,\"breed\":\"groodle\",\"name\":\"Henry\"}" | STRING         |
| :map                 | Ash.Type.Map                         | Map                | %{name: "Henry", age: 8, breed: :groodle}               | "{\"age\":8,\"breed\":\"groodle\",\"name\":\"Henry\"}" | STRING         |
| :module              | Ash.Type.Module                      | Module             | AshNeo4j.DataLayer                                      | "Elixir.AshNeo4j.DataLayer"                            | STRING         |
| :naive_datetime      | Ash.Type.NaiveDateTime               | NaiveDateTime      | ~N[2025-05-11 07:45:41]                                 | 2025-05-11T07:45:41                                    | LOCAL_DATETIME |
| :string              | Ash.Type.String                      | BitString          | "hello"                                                 | "hello"                                                | STRING         |
| subtype_of: :struct  | DogStruct using Ash.Type.NewType     | DogStruct          | %DogStruct{name: "Henry", age: 8, breed: :groodle}      | "{\"age\":8,\"breed\":\"groodle\",\"name\":\"Henry\"}" | STRING         |
| :time                | Ash.Type.Time                        | Time               | ~T[07:45:41Z]                                           | 07:45:41Z                                              | TIME           |
| :time_usec           | Ash.Type.TimeUsec                    | Time               | ~T[07:45:41.429903Z]                                    | 07:45:41.429903000Z                                    | TIME           |
| subtype_of: :tuple   | DogTuple using Ash.Type.NewType      | Tuple              | {"Henry", 8, :groodle}                                  | "{\"age\":8,\"breed\":\"groodle\",\"name\":\"Henry\"}" | STRING         |
| :subtype_of :struct  | DogTypedStruct using Ash.TypedStruct | DogTypedStruct     | %DogTypedStruct{name: "Henry", age: 8, breed: :groodle} | "{\"age\":8,\"breed\":\"groodle\",\"name\":\"Henry\"}" | STRING         |
| :union               | Ash.Type.Union                       | Ash.Union          | %Ash.Union{type: :typed_struct, value: %Dog{age: 8}}    | "{\"type\":\"typed_struct\",\"value\":{\"age\":8}}"    | STRING         |
| :url_encoded_binary  | Ash.Type.UrlEncodedBinary            | BitString          | <<1, 2, 3>>                                             | "AQID"                                                 | STRING         |
| :utc_datetime        | Ash.Type.UtcDatetime                 | DateTime           | ~U[2025-05-11 07:45:41Z]                                | 2025-05-11T07:45:41Z                                   | DATETIME       |
| :utc_datetime_usec   | Ash.Type.UtcDatetimeUsec             | DateTime           | ~U[2025-05-11 07:45:41.429903Z]                         | 2025-05-11T07:45:41.429903000Z.                        | DATETIME       |
| :uuid                | Ash.Type.UUID                        | BitString          | "0274972c-161c-4dc9-882f-6851704c2af9"                  | "0274972c-161c-4dc9-882f-6851704c2af9"                 | STRING         |
| :uuid7               | Ash.Type.UUIDv7                      | BitString          | "019d85f7-8450-7695-9426-4ede74026140"                  | "019d85f7-8450-7695-9426-4ede74026140"                 | STRING         |
| (vector embedding)   | AshNeo4j.Types.Vector                | List               | [0.12, -0.04, 0.98]                                     | [0.12, -0.04, 0.98]                                    | LIST<FLOAT>    |

Ash :date, :datetime, :time and :naive_datetime are second precision, whereas :utc_datetime_usec and :time_usec are microsecond precision. Neo4j is capable of nanoseconds however Ash/Elixir is not. 

Struct is supported, however must implement Ash.Type. Ash arrays are supported as arrays in neo4j.

Ash.Type.NewType including Ash.TypedStruct are supported, as are embedded resources.

Ash.Type.File and Ash.Type.Term are not supported. The built-in `Ash.Type.Vector` is also not supported — AshNeo4j ships its own `AshNeo4j.Types.Vector` for embeddings (stored as a Neo4j `LIST<FLOAT>`), with `vector_similarity` / `vector_cosine_distance` search expressions. See `usage-rules/vectors.md`.

## Storage Types

Generally AshNeo4j uses Ash.Type.dump_to_native and Ash.Type.cast_stored. Post/prior to this we may encode/decode either as JSON or Base64.

Ash.Type.Keyword, Ash.Type.Map, Ash.Type.Struct, Ash.Type.Tuple and Ash.Type.Union are stored as JSON.
Ash.Type that have storage type map and aren't built in are also stored as JSON. This covers TypedStruct, embedded resources and Ash.Type.NewType you create subtype_of keyword, map, struct, tuple or union.

JSON types are stored as maps. We encode with AshNeo4j.Util.json_encode, which erases Struct's and orders keys. It deliberately avoids using Jason.Encoder on structs other than those it has converted to Jason.OrderedObject. This means you are free to use Jason.Encoder (possibly via [ash_jason](https://hexdocs.pm/ash_jason/)) for other concerns such as presentation or communications.

Interestingly many Ash.Types have identical JSON representations (e.g. Map, Struct, Tuple, Keyword). Neo4j lists are used for arrays since JSON and Base64 are strings.

A few things to note:
* Ash.Type.UUID, Ash.Type.UUIDv7 - we persist in the 'cast_input' format rather than as compacted binary for readability, so we don't use Ash.Type.dump_to_native and Ash.Type.cast_stored at all. However foreign keys aren't persisted using properties, we of course use relationships.
* Ash.Type.Function - we persist external functions as a string MFA, rather than binary, so we don't use Ash.Type.dump_to_native and Ash.Type.cast_stored at all. Persisting local functions is not supported.

## Keys

We've generally used :uuid_primary_key, which Ash creates. While it *may* be possible to use other types for primary keys, we haven't done so yet.

## Elixir nil and Neo4j Null

Generally attributes with nil value are not persisted, rather they are simply not created or removed on update to nil.

## Other Notable

Transactions are supported.

## Aggregates

AshNeo4j supports Ash aggregates. Declare them in the standard Ash `aggregates` block:

```elixir
aggregates do
  count :comment_count, :comments
  exists :has_comments, :comments
  sum :total_score, :comments, field: :score
  avg :avg_score, :comments, field: :score
  min :min_score, :comments, field: :score
  max :max_score, :comments, field: :score
  first :first_comment_title, :comments, field: :title
  list :comment_titles, :comments, field: :title
end
```

Supported kinds: `:count`, `:exists`, `:sum`, `:avg`, `:min`, `:max`, `:first`, `:list`. The `:custom` kind is not supported.

Aggregates are computed in Cypher via `OPTIONAL MATCH` traversal. Single-hop and multi-hop relationship paths are both supported.

**Embedded struct and JSON-type fields are supported.** When `field:` refers to an attribute stored as JSON — `Ash.TypedStruct`, `Ash.Type.NewType` with map storage, embedded resources, `Ash.Type.Map`, `Ash.Type.Union`, etc. — AshNeo4j collects the raw JSON strings from Neo4j and deserializes them in Elixir using `Ash.Type.cast_stored/3`. `:list` and `:first` aggregates return fully deserialized struct values. `:sum`, `:avg`, `:min`, `:max` work when the deserialized values are directly comparable/numeric. To aggregate a sub-field within a struct, use an `expr:` aggregate.

```elixir
aggregates do
  list :all_metadata, :related_things, field: :metadata   # returns [%MetadataStruct{}, ...]
  first :first_metadata, :related_things, field: :metadata # returns %MetadataStruct{}
end

# No elevation needed — navigate into the struct with an expression aggregate:
Ash.aggregate(MyResource, {:total_bandwidth, :sum, [
  path: [:characteristics],
  expr: Ash.Expr.expr(get_path(value, [:bandwidth])),
  expr_type: :integer
]})
```

For `expr:` aggregates, AshNeo4j fetches full destination records, evaluates the Ash expression on each in Elixir, and aggregates the results. Any valid Ash expression works — `get_path` for nested struct navigation, arithmetic, etc. Note: `expr:` is a programmatic API and is not available in the resource-level `aggregates do` DSL block.

## Calculations

AshNeo4j supports **expression calculations** — calculations declared with `expr(...)` in the `calculations` block. They are evaluated in Elixir after records are loaded from Neo4j.

```elixir
calculations do
  calculate :score_doubled, :integer, expr(score * 2)
  calculate :full_name, :string, expr(first_name <> " " <> last_name)
  calculate :dog_age, :integer, expr(get_path(dog, [:age]))
end
```

Calculations can be:

- **Loaded** — `Ash.load!(records, [:score_doubled])`
- **Filtered on** — `Ash.Query.filter(score_doubled > 10)` — AshNeo4j loads all matching nodes then evaluates the filter in Elixir
- **Sorted on** — `Ash.Query.sort(score_doubled: :asc)` — applied in Elixir after records are loaded

**Embedded struct fields work without elevation.** `get_path(dog, [:age])` navigates into a `DogTypedStruct` directly — records arrive with embedded types fully deserialized, so any Ash expression that works in-memory works in a calculation.

Only `expr(...)` calculations are currently supported. Custom `:calculate` callback modules are not.

## Limitations and Future Work

Ash Neo4j has support for Ash create, update, read, destroy actions, aggregates, expression calculations, spatial types, and vector embeddings. The cypher is now parameterised but is by no means optimised. The DSL is likely to evolve further and this may break back compatibility. Storage formats are subject to infrequent change so upgrade *may* require data migration (not included).

Vector similarity search is currently a full scan — Neo4j does not use the HNSW vector index for `vector.similarity.cosine` in a `WHERE`/`ORDER BY`. Indexed top-K (via `db.index.vector.queryNodes` / the Cypher 25 `SEARCH` clause) is tracked in [#297](https://github.com/diffo-dev/ash_neo4j/issues/297).

Future work may include: cached calculations and aggregates, indexed vector/semantic search ([#297](https://github.com/diffo-dev/ash_neo4j/issues/297)), and broader geospatial support.

Collaboration on ash_neo4j welcome via github, please use discussions and/or raise issues as you encounter them. If going straight for a PR, please include explanation and test cases.

## Acknowledgements

Thanks to the [Ash Core](https://github.com/ash-project) for [ash](https://github.com/ash-project/ash) 🚀, including [ash_csv](https://github.com/ash-project/ash_csv) which was an exemplar.

Thanks to [Sagastume](https://github.com/sagastume) for [boltx](https://github.com/tiagodavi/ex4j) which was based on [bolt_sips](https://github.com/florinpatrascu/bolt_sips) by [Florin Patrascu](https://github.com/florinpatrascu).

Thanks to the [Neo4j Core](https://github.com/neo4j) for [neo4j](https://github.com/neo4j/neo4j) and pioneering work on graph databases. Thanks to [DozerDB](https://dozerdb.org) for enterprise features on community neo4j.

## Links

[Diffo.dev](https://www.diffo.dev)
[Neo4j Deployment Centre](https://neo4j.com/deployment-center/).
