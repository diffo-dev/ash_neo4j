# AshNeo4j

[![Module Version](https://img.shields.io/hexpm/v/ash_neo4j)](https://hex.pm/packages/ash_neo4j)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen)](https://hexdocs.pm/ash_neo4j/)
[![License](https://img.shields.io/hexpm/l/ash_neo4j)](https://github.com/diffo-dev/ash_neo4j/blob/master/LICENSE.md)

Ash DataLayer for Neo4j, configurable using a simple DSL

## Installation

Add to the deps:

```elixir
def deps do
  [
    {:ash_neo4j, "~> 0.1.4"},
  ]
end
```

## Usage

Configure `AshNeo4j.DataLayer` as `data_layer:` within `use Ash.Resource` options:

```elixir
  use Ash.Resource,
    data_layer: AshNeo4j.DataLayer
```

### Configuration

Each Ash.Resource requires configuration of its AshNeo4j.DataLayer. An example Comment resource is given below, it can belong to a Post resource.

```elixir
defmodule Comment.Resource do
  use Ash.Resource,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    label :Comment
    relate [{:post, :BELONGS_TO, :outgoing}]
    translate id: :uuid
  end

  actions do
    default_accept(:*)
    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string, public?: true)
  end

  relationships do
    belongs_to(:post, Post, public?: true)
  end
end
```

## Label

The DSL is used to label the Ash Resource's underlying graph node.

```elixir
  neo4j do
    label :Comment
  end
```

## Relate

The DSL is used to direct any node relationships.
```elixir
  neo4j do
    relate [{:post, :BELONGS_TO, :outgoing}]
  end
```

## Translate

The DSL may be used to translate the Ash Resource's attributes to node properties.
```elixir
  neo4j do
    translate id: :uuid
  end
```

## Skip

The DSL may be used to skip storing attributes as node properties. This is typically used for foreign keys, which not required with relate.
```elixir
  neo4j do
    skip [:other_id]
  end
```

## Verifiers

The DSL is verified against misconfiguration and violation of accepted neo4j conventions providing compile time errors:

* label: neo4j label must be CamelCase
* neo4j: neo4j property names should start with a letter and may contain numbers and underscores
* relate: relationship_name must match the name of a relationship
* relate: edge label must be upper case and may have an underscore
* translate: :id attribute must be translated

## Installing Neo4j and Configuring Boltx

ash_neo4j uses [neo4j](https://github.com/neo4j/neo4j) which must be installed and running.

Your Ash application needs to configure, start and supervise [boltx](https://github.com/sagastume/boltx), see [boltx documentation](https://hexdocs.pm/boltx/). Make sure to configure any required authorisation.

I've used Neo4j community edition 4.4 (bolt 4.4) and to connect using boltx I needed to also set the environment variable ```BOLT_VERSIONS=4.4``` to steer [bolt protocol handshake] (https://neo4j.com/docs/bolt/current/bolt/handshake).

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

## Elixir nil and Neo4j Null

Generally attributes with nil value are not persisted, rather than created with Null value. However values of nil within string quoted 'Elixir' types (keyword, tuple, map and struct) are persisted.

## Limitations and Future Work

Ash Neo4j is early stage, it is likely that the dsl will evolve and this may break back compatibility. Ash Neo4j is in 'build' phase with initial support for Ash create, update, read, destroy actions. Collaboration on ash_neo4j welcome via github, please use discussions and/or raise issues as you encounter them.

## Acknowledgements

Thanks to the [Ash Core](https://github.com/ash-project) for [ash](https://github.com/ash-project/ash) 🚀, including [ash_csv](https://github.com/vonagam/ash_jason) which was an exemplar.

Thanks to [Sagastume](https://github.com/sagastume) for [boltx](https://github.com/tiagodavi/ex4j) which AFAIK was based on [bolt_sips](https://github.com/florinpatrascu/bolt_sips) by [Florin Patrascu](https://github.com/florinpatrascu).

Thanks to the [Neo4j Core](https://github.com/neo4j) for [neo4j](https://github.com/neo4j/neo4j) and pioneering work on graph databases.

## Links

[Diffo.dev](https://www.diffo.dev)
[Neo4j Deployment Centre](https://neo4j.com/deployment-center/).
