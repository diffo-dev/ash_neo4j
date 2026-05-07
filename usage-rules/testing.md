<!--
SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Testing

## AshNeo4j.Sandbox

Use `AshNeo4j.Sandbox` for test isolation. Each test gets a dedicated Neo4j connection with an open transaction. All queries from that test run inside the transaction, which is rolled back automatically when the test process exits — nothing is ever committed, so there is no data to clean up.

Do not use `delete_all` teardown patterns. Use the sandbox instead.

## Setup

Start Bolty once for the test suite, then check out a sandbox connection per test:

```elixir
setup_all do
  AshNeo4j.BoltyHelper.start()
end

setup do
  AshNeo4j.Sandbox.checkout()
  on_exit(&AshNeo4j.Sandbox.rollback/0)
end
```

`on_exit(&AshNeo4j.Sandbox.rollback/0)` is optional — the transaction rolls back automatically when the test process exits — but is recommended for clarity.

## Verifying the graph directly

Use `AshNeo4j.Neo4jHelper` to assert on nodes and edges at the graph level, independently of the Ash query layer:

```elixir
# Assert a node exists with specific properties
{:ok, %{records: records}} = AshNeo4j.Neo4jHelper.read_nodes(:Post, %{uuid: post.id})
assert length(records) == 1

# Assert a direct edge exists between two nodes
assert AshNeo4j.Neo4jHelper.nodes_relate_how?(
  :Post, %{uuid: post.id},
  :Comment, %{uuid: comment.id},
  :HAS_COMMENT, :outgoing
)

# Assert a relationship via multi-hop traversal
assert AshNeo4j.Neo4jHelper.nodes_relate_how?(
  :Author, %{uuid: author.id},
  :Tag, %{uuid: tag.id},
  [WROTE: :outgoing, TAGGED_WITH: :outgoing]
)
```

These helpers operate **below the Ash data layer** — they talk directly to Neo4j via Bolty and know nothing about Ash resources, types, or translations. You must supply already-translated values: the same property names and labels that AshNeo4j's compile-time translation map produces. You are responsible for:

- Property names must be in Neo4j form (`camelCase`; `uuid` not `id` for a UUID primary key)
- Property values must be in their stored Neo4j form (e.g. the raw UUID string, not an Ash struct)
- **Labels**: any label present on the node is valid. The recommended approach is to pass both the domain label and the module label as a pair — this asserts both are present and uniquely identifies the resource type: `read_nodes([:Access, :Shelf], %{uuid: shelf.id})`. Use `AshNeo4j.Resource.Info.domain_label/1` and `module_label/1` to obtain these programmatically.

Return values from `read_nodes` and similar are `{:ok, %Bolty.Response{}}` structs — not Ash records. `nodes_relate_how?` returns `true`, `false`, or `:error`.

## Parallel tests

Because each test's writes are confined to an uncommitted transaction, tests can run concurrently without interfering:

```elixir
use ExUnit.Case, async: true

setup do
  AshNeo4j.Sandbox.checkout()
  on_exit(&AshNeo4j.Sandbox.rollback/0)
end
```
