# AshNeo4j

[![Module Version](https://img.shields.io/hexpm/v/ash_neo4j)](https://hex.pm/packages/ash_neo4j)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen)](https://hexdocs.pm/ash_outstanding/)
[![License](https://img.shields.io/hexpm/l/ash_outstanding)](https://github.com/diffo-dev/ash_outstanding/blob/master/LICENSE.md)

Ash datalayer for Neo4j

## Installation

Add to the deps:

```elixir
def deps do
  [
    {:ash_neo4j, "~> 0.1.0"},
  ]
end
```

## Usage

Configure `AshNeo4j.Datalayer` as `data_layer:` within `use Ash.Resource` options:

```elixir
  use Ash.Resource,
    data_layer: AshNeo4j.DataLayer
```

### Configuration

Generally you will want to configure your Ash Resource so that outstanding?(expected, actual) is true when the essentials of your Ash Resource are satisfied. This may align to expecting actual to sufficiently attributes which are mandatory and/or fundamental to Ash identities. These attributes are configured using the expect list.

- expect, provide list of Ash Record fields which can have have expectations

Here is an example `outstanding` dsl section, which configures a Specification resource so that we can set expectations on any or all of the values of keys :name, :major_version and :version while ignoring other fields in the expected/actual resource.
When nil_outstanding?(expected, actual) is true, outstanding(expected, actual) returns nil
When nil_outstanding?(expected, actual) is false, outstanding(expected, actual) returns a struct of your Ash Record with just the unmet expectations.

```elixir
defmodule Comment.Resource do
  use Ash.Resource,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    label :Comment
    store [:id, :title]
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

## Store

The DSL is used to store the Ash Resource's attributes as node properties, without translation.
```elixir
  neo4j do
    store [:id, :title, :score, :public, :unique]
  end
```

## Translate

The DSL may be used to translate the Ash Resource's attributes to node properties.
        
        translate id: :uuid

## Acknowledgements
Thanks to [Tiago Davi](https://github.com/tiagodavi) for [ex4j] (https://github.com/tiagodavi/ex4j) which is used by ash_neo4j

Kudos to the [Ash Core](https://github.com/ash-project) for [ash](https://github.com/ash-project/ash), including [ash_csv](https://github.com/vonagam/ash_jason) which was an exemplar 🚀

## Links
[Diffo.dev](https://www.diffo.dev)
[Neo4j Deployment Centre](https://neo4j.com/deployment-center/).
