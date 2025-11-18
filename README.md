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

Add to the deps:

```elixir
def deps do
  [
    {:ash_neo4j, "~> 0.2.12"},
  ]
end
```

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
    translate id: :uuid
  end

  actions do
    default_accept :*
    defaults [:create, :read, :update, :destroy]
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
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
    relate [{:WRITTEN_BY, :outgoing, :Post}]
  end
```

Guard is useful where the resource has no explicit relationships, but other resources expect the resource to exist while they are related.
Guard can also be used where the underlying node has other edges which should prevent resource destruction.

## Translate

The DSL may be used to translate the Ash Resource's attributes to node properties. By default the id attribute will be translated according to the 'short name' of the type, such that the following declaration is unneccessary for an Ash.Type.UUID primary key.
```elixir
  neo4j do
    translate id: :uuid
  end
```

Attributes with underscores are translated to camelCase Neo4j properties so don't need to be explicitly listed in translate.

## Skip

The DSL may be used to skip storing attributes as node properties. This can be useful for 'transient' attributes, or attributes you want to default using the resource but not store explicitly.

```elixir
  neo4j do
    skip [:other_id]
  end
```

## Verifiers

The DSL is verified against misconfiguration and violation of accepted neo4j conventions providing compile time errors:

* neo4j labels must be PascalCase
* neo4j property names must be camelCase
* edge label must be MACRO_CASE
* edge direction must be in [:incoming, :outgoing]
* relate: relationship_name must match the name of a relationship
* relate: relationship enrichment not possible, edge_label, edge_direction and destination_label must be unique

## Installing Neo4j and Configuring Boltx

ash_neo4j uses [neo4j](https://github.com/neo4j/neo4j) which must be installed and running.

Your Ash application needs to configure, start and supervise [boltx](https://github.com/sagastume/boltx), see [boltx documentation](https://hexdocs.pm/boltx/). Make sure to configure any required authorisation.

I've used Neo4j community edition 4.4 (bolt 4.4) and 5.28 (boltx limits to bolt 5.4) and any version in between *should* work. To connect to Neo4j 4.4 using boltx I needed to also set the environment variable ```BOLT_VERSIONS="4.4"``` to steer [bolt protocol handshake] (https://neo4j.com/docs/bolt/current/bolt/handshake).  I've raised [negotiate range](https://github.com/sagastume/boltx/pull/125) on boltx to improve version negotiation so that this won't be necessary.

## Elixir, Ash and Neo4j Types

We've made some decisions around how Ash/Elixir types are used to persist attributes as Neo4j properties. Where possible we've used 'native' Neo4j types, where this is not possible we've simply quoted to strings. Ash Array support is limited by Neo4j to lists of simple types which must be homogenous.


| Ash Type shortname  | Ash Type Module           | Elixir Type Module | Attribute Value Example                                | Neo4j Node Property Value Cypher Example               | Cypher Type    |
|---------------------|---------------------------|--------------------|--------------------------------------------------------|--------------------------------------------------------|----------------|
| :atom               | Ash.Type.Atom             | Atom               | :a                                                     | ":a"                                                   | STRING         |
| :binary             | Ash.Type.Binary           | BitString          | <<1, 2, 3>>                                            | "\u0001\u0002\u0003"                                   | STRING         |
| :boolean            | Ash.Type.Boolean          | Boolean            | true                                                   | true                                                   | BOOLEAN        |
| :integer            | Ash.Type.Integer          | Integer            | 1                                                      | 1                                                      | INTEGER        |
| :float              | Ash.Type.Float            | Float              | 1.23456789                                             | 1.23456789                                             | FLOAT          |
| :string             | Ash.Type.String           | BitString          | "hello"                                                | "hello"                                                | STRING         |
| :tuple              | Ash.Type.Tuple            | Tuple              | \{:a, 1, false\}                                         | "\{:a, 1, false\}"                                       | STRING         |
| :keyword            | Ash.Type.Keyword          | Keyword            | [\{:a, :atom\}, \{:s, "string"\}]                          | ["\{:a, :atom}\","\{:s, string\}"]                         | LIST           |
| :map                | Ash.Type.Map              | Map                | %\{c: false, a: "a", b: 1, n: nil\}                      | "%\{c: false, a: "a", b: 1, n: nil\}"                    | STRING         |
| :mapset             | Ash.Type.MapSet           | MapSet             | MapSet.new([1, false, :two])                           | "MapSet.new([1, false, :two])"                         | STRING         |
| :struct             | Ash.Type.Struct           | Struct             | %MyApp.Struct{a: :a, s: "Hello"}                       | "%MyApp.Struct\{a: :a, s: \"Hello\"\}"                   | STRING         |
| :uuid               | Ash.Type.UUID             | BitString          | "0274972c-161c-4dc9-882f-6851704c2af9"                 | "0274972c-161c-4dc9-882f-6851704c2af9                  | STRING         |
| :url_encoded_binary | Ash.Type.UrlEncodedBinary | BitString          | "aHR0cHM6Ly93d3cuZGlmZm8uZGV2Lw"                       | "aHR0cHM6Ly93d3cuZGlmZm8uZGV2Lw                        | STRING         |
| :decimal            | Ash.Type.Decimal          | Decimal            | Decimal.new("4.2")                                     | "Decimal.new(\"4.2\")"                                 | STRING         |
| :ci_string          | Ash.Type.CiString         | BitString          | "HELLO"                                                | "HELLO"                                                | STRING         |
| :function           | Ash.Type.Function         | Function           | &AshNeo4j.Neo4jHelper.create_node/2                    | "&AshNeo4j.Neo4jHelper.create_node/2"                  | STRING         |
| :module             | Ash.Type.Module           | Module             | AshNeo4j.DataLayer                                     | ":Elixir.AshNeo4j.DataLayer"                           | STRING         |
| :regex              | Ash.Type.Regex            | Regex              | ~r/foo/iu                                              | "~r/foo/iu"                                            | STRING         |
| \{:array, :atom\}     | -                         | List               | [:a,:b,:c]                                             | [":a",":b",":c"]                                       | LIST           |
| \{:array, :boolean\}  | -                         | List               | [true,true,false]                                      | [true,true,false]                                      | LIST           |
| \{:array, :integer\}  | -                         | List               | [1,2,3]                                                | [1,2,3]                                                | LIST           |
| \{:array, :map\}      | -                         | List               | [%MyApp.Struct\{a: :a, s: "Hello"\}]                     | ["%MyApp.Struct\{a: :a, s: \"Hello\"\}"]                 | LIST           |
| \{:array, :term\}     | -                         | List               | [%MyApp.Struct\{a: :a, s: "Hello"\}]                     | ["%MyApp.Struct\{a: :a, s: \"Hello\"\}"]                 | LIST           |
| :date               | Ash.Type.Date             | Date               | ~D[2025-02-25]                                         | 2025-05-11                                             | DATE           |
| :datetime           | Ash.Type.DateTime         | DateTime           | ~U[2025-02-25 11:59:00Z]                               | 2025-05-11T07:45:41Z                                   | ZONED_DATETIME |
| :utc_datetime_usec  | Ash.Type.UtcDateTimeUsec  | DateTime           | ~U[2025-02-25 11:59:00.123456Z]                        | 2025-05-11T07:45:41.429903Z                            | ZONED_DATETIME |
| :naive_datetime     | Ash.Type.NaiveDateTime    | NaiveDateTime      | ~N[2025-05-11 07:45:41]                                | 2025-05-11T07:45:41                                    | LOCAL_DATETIME |
| :time               | Ash.Type.Time             | Time               | ~T[07:45:41Z]                                          | 07:45:41                                               | TIME           |
| :time_usec          | Ash.Type.TimeUsec         | Time               | ~T[07:45:41.429903Z]                                   | 07:45:41.429903                                        | TIME           |
| :duration           | Ash.Type.Duration         | Duration           | %Duration{month: 2}                                    | PT2H                                                   | DURATION       |

Ash :date, :datetime, :time and :naive_datetime are second precision, whereas :utc_datetime_usec and :time_usec are microsecond precision. Note that :time_usec requires ash ~> 3.5.10 (to be released).

## Structs and String.Chars

Structs (including Ash embedded resources) are supported and stored in their string representation, this requires String.Chars to be implemented using the representation common for Elixir structs. This is straightforward whether or not you own the module. For most structs you can simply use inspect(struct), however for an embedded Ash.Resource don't want the metadata in the property value. Here is an example for a simple embedded resource:

```elixir
defmodule Money do
  use Ash.Resource,
    data_layer: :embedded

  attributes do
    attribute :amount, :integer
    attribute :currency, :atom
  end

  defimpl String.Chars do
    def to_string(struct) do
      inspect(Ash.Test.strip_metadata(struct)) |> String.replace(", __meta__: #Ecto.Schema.Metadata<>", "")
    end
  end
end
```

Here is a resulting node property value 
```elixir
'%AshNeo4j.Test.Resource.Money{amount: 1000, currency: :sek}'
```

## Elixir nil and Neo4j Null

Generally attributes with nil value are not persisted, rather they are simply not created or removed on update to nil. However values of nil within string quoted 'Elixir' types (keyword, tuple, map and struct) are persisted.

## Limitations and Future Work

Ash Neo4j has initial support for Ash create, update, read, destroy actions. Calculations are supported but not evaluated in Neo4j itself. Aggregates are not yet supported. The DSL is likely to evolve further and this may break back compatibility. Collaboration on ash_neo4j welcome via github, please use discussions and/or raise issues as you encounter them.

## Acknowledgements

Thanks to the [Ash Core](https://github.com/ash-project) for [ash](https://github.com/ash-project/ash) 🚀, including [ash_csv](https://github.com/vonagam/ash_jason) which was an exemplar.

Thanks to [Sagastume](https://github.com/sagastume) for [boltx](https://github.com/tiagodavi/ex4j) which was based on [bolt_sips](https://github.com/florinpatrascu/bolt_sips) by [Florin Patrascu](https://github.com/florinpatrascu).

Thanks to the [Neo4j Core](https://github.com/neo4j) for [neo4j](https://github.com/neo4j/neo4j) and pioneering work on graph databases.

## Links

[Diffo.dev](https://www.diffo.dev)
[Neo4j Deployment Centre](https://neo4j.com/deployment-center/).
