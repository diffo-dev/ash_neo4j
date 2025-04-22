# AshNeo4j

[![Module Version](https://img.shields.io/hexpm/v/ash_neo4j)](https://hex.pm/packages/ash_neo4j)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen)](https://hexdocs.pm/ash_outstanding/)
[![License](https://img.shields.io/hexpm/l/ash_outstanding)](https://github.com/diffo-dev/ash_outstanding/blob/master/LICENSE.md)

Ash datalayer for Neo4j, configurable using a simple DSL

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

Each Ash.Resource requires configuration of its AshNeo4j.DataLayer. An example Comment resource is given below, it can belong to a Post resource.

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
```elixir
  neo4j do
    translate id: :uuid
  end
```

## Limitations and Future Work

Currently ash_neo4j inherits the read-only limitation from [ex4j](https://github.com/tiagodavi/ex4j). Ideally ex4j would be extended and ash_neo4j would lever this to support create, update and destroy actions. [bolt_sips](https://github.com/florinpatrascu/bolt_sips) is not maintained and should be replaced by [boltx](https://github.com/sagastume/boltx). Collaboration on ash_neo4j and/or upstream dependencies welcome via github.

## Acknowledgements

Thanks to the [Ash Core](https://github.com/ash-project) for [ash](https://github.com/ash-project/ash) 🚀, including [ash_csv](https://github.com/vonagam/ash_jason) which was an exemplar.

Thanks to [Tiago Davi](https://github.com/tiagodavi) for [ex4j](https://github.com/tiagodavi/ex4j) which is limited to reads.

Thanks to [Florin Patrascu](https://github.com/florinpatrascu) for [bolt_sips](https://github.com/florinpatrascu/bolt_sips) which is used by both ash_neo4j and ex4j.

Thanks to the [Neo4j Core](https://github.com/neo4j) for [neo4j](https://github.com/neo4j/neo4j) which pioneered graph databases.

## Links

[Diffo.dev](https://www.diffo.dev)
[Neo4j Deployment Centre](https://neo4j.com/deployment-center/).
