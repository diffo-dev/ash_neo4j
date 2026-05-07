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

## Installing Neo4j and Configuring Bolty

ash_neo4j uses [neo4j](https://github.com/neo4j/neo4j) which must be installed and running.

ash_neo4j uses [bolty](https://github./com/diffo-dev/bolty), a reluctant fork of [boltx](https://github.com/sagastume/boltx)

Your Ash application needs to configure, start and supervise bolty see [bolty documentation](https://hexdocs.pm/bolty/). Make sure to configure any required authorisation.

I've used a few Neo4j 5.x community edition's up to 5.6.22 (bolty limits to bolt 5.4). I've also used [DozerDB](https://dozerdb.org) 5.26.3 with multi-database. I don't recommend either Neo4j 4.x or Neo4 5.x with BOLT BOLT 4.x, while it *should* work I haven't regressioned tested these.

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

Ash :date, :datetime, :time and :naive_datetime are second precision, whereas :utc_datetime_usec and :time_usec are microsecond precision. Neo4j is capable of nanoseconds however Ash/Elixir is not. 

Struct is supported, however must implement Ash.Type. Ash arrays are supported as arrays in neo4j.

Ash.Type.NewType including Ash.TypedStruct are supported, as are embedded resources.

Ash.Type.File, Ash.Type.Term and Ash.Type.Vector are not supported.

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

## Limitations and Future Work

Ash Neo4j has support for Ash create, update, read, destroy actions. The cypher is now parameterised but is by no means optimised. The DSL is likely to evolve further and this may break back compatibility. Storage formats are subject to infrequent change so upgrade *may* require data migration (not included).

Future work may include: calculations, aggregates, vectors/semantic search, geospatial support.

Collaboration on ash_neo4j welcome via github, please use discussions and/or raise issues as you encounter them. If going straight for a PR, please include explanation and test cases.

## Acknowledgements

Thanks to the [Ash Core](https://github.com/ash-project) for [ash](https://github.com/ash-project/ash) 🚀, including [ash_csv](https://github.com/ash-project/ash_csv) which was an exemplar.

Thanks to [Sagastume](https://github.com/sagastume) for [boltx](https://github.com/tiagodavi/ex4j) which was based on [bolt_sips](https://github.com/florinpatrascu/bolt_sips) by [Florin Patrascu](https://github.com/florinpatrascu).

Thanks to the [Neo4j Core](https://github.com/neo4j) for [neo4j](https://github.com/neo4j/neo4j) and pioneering work on graph databases. Thanks to [DozerDB](https://dozerdb.org) for enterprise features on community neo4j.

## Links

[Diffo.dev](https://www.diffo.dev)
[Neo4j Deployment Centre](https://neo4j.com/deployment-center/).
