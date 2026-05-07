<!--
SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Setup

## Bolty and the Bolt protocol

AshNeo4j connects to Neo4j via the [Bolt protocol](https://neo4j.com/docs/bolt/current/) using [Bolty](https://hexdocs.pm/bolty/), a DBConnection-based driver. Bolty is a required dependency of AshNeo4j — you do not add it separately.

There is no `Ecto.Repo`. Instead, Bolty runs as a named process (`Bolt`) in your application's supervision tree, backed by a DBConnection pool.

## Configuration

Add connection config to `config/runtime.exs` (credentials should not be in `config/config.exs`):

```elixir
config :bolty, Bolt,
  uri: "bolt://localhost:7687",
  auth: [username: "neo4j", password: "password"],
  pool_size: 10,
  name: Bolt
```

`name: Bolt` is required — AshNeo4j always refers to the connection pool by the name `Bolt`.

## Supervision tree

Add Bolty to your application's children in `lib/my_app/application.ex`:

```elixir
def start(_type, _args) do
  children = [
    {Bolty, Application.get_env(:bolty, Bolt)},
    # ...
  ]

  Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
end
```

## Igniter

If your project uses Igniter, the above can be done automatically:

```bash
mix igniter.install ash_neo4j
```
