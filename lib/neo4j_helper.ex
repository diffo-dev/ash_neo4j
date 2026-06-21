# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Neo4jHelper do
  require Logger
  alias AshNeo4j.Cypher
  alias AshNeo4j.Cypher.Query

  @moduledoc """
  AshNeo4j DataLayer Neo4j Helper
  """

  @doc """
  Creates a neo4j node with labels and properties

  ## Examples
  ```
  iex> {result, _} = AshNeo4j.Neo4jHelper.create_node([:Cinema, :Actor], %{name: "Bill Nighy"})
  iex> result
  :ok
  ```
  """
  def create_node(labels, properties) when is_list(labels) and is_map(properties) do
    Query.create_node(labels, properties)
    |> Cypher.run()
  end

  @spec delete_all() ::
          {:error, %{:__exception__ => true, :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, any()}
  @doc """
  Delete all neo4j nodes and relationships

  ## Examples
  ```
  iex> {result, _} = AshNeo4j.Neo4jHelper.delete_all()
  iex> result
  :ok
  ```
  """
  def delete_all() do
    Cypher.run("MATCH (n) DETACH DELETE n")
  end

  @spec delete_nodes(atom()) ::
          {:error, %{:__exception__ => true, :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, any()}
  @doc """
  Delete neo4j nodes

  ## Examples
  ```
  iex> {result, _} = AshNeo4j.Neo4jHelper.delete_nodes(:Actor)
  iex> result
  :ok
  iex> AshNeo4j.Neo4jHelper.create_node([:Actor], %{name: "Bill Nighy"})
  iex> {result, _} = AshNeo4j.Neo4jHelper.delete_nodes(:Actor, %{name: "Bill Nighy"})
  iex> result
  :ok
  ```
  """
  def delete_nodes(label, properties \\ %{}) when is_atom(label) and is_map(properties) do
    Query.delete_nodes(label, properties)
    |> Cypher.run()
  end

  @doc """
  Safely delete neo4j nodes, delete is guarded by relationships

  ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node([:Actor], %{name: "Keira Knightley"})
  iex> AshNeo4j.Neo4jHelper.create_node([:Movie], %{title: "Love Actually"})
  iex> AshNeo4j.Neo4jHelper.create_node([:Movie], %{title: "Bend it Like Beckham"})
  iex> AshNeo4j.Neo4jHelper.relate_nodes(:Actor, %{name: "Keira Knightley"}, [{:Movie, %{title: "Love Actually"}, :ACTED_IN, :outgoing, false},
  ...> {:Movie, %{title: "Bend it Like Beckham"}, :ACTED_IN, :outgoing, false}])
  iex> {result, _} = AshNeo4j.Neo4jHelper.safe_delete_nodes(:Actor, %{name: "Keira Knightley"}, [{:ACTED_IN, :outgoing, :Movie}, {:LIVES_AT, :outgoing, :Place}])
  iex> result
  :error
  iex> {result, _} = AshNeo4j.Neo4jHelper.safe_delete_nodes(:Actor, %{name: "Keira Knightley"}, [{:LIVES_AT, :outgoing, :Place}])
  iex> result
  :ok
  ```
  """
  def safe_delete_nodes(label, properties, relationships) when is_atom(label) or is_list(label) do
    Query.delete_nodes_guarded(label, properties, relationships)
    |> Cypher.run_expecting_deletions()
  end

  @doc """
  Single filtered + guarded destroy (#361): deletes the `id`-matched node when it
  satisfies `filter_conditions` (optimistic lock) and isn't `guard`-protected.
  `{:ok, _}` when deleted, `{:error, :nothing_deleted}` otherwise.
  """
  def delete_node_filtered(label, id_props, filter_conditions, guards)
      when (is_atom(label) or is_list(label)) and is_map(id_props) and is_list(filter_conditions) and
             is_list(guards) do
    Query.delete_node_filtered(label, id_props, filter_conditions, guards)
    |> Cypher.run_expecting_deletions()
  end

  @doc """
  The optimistic-lock existence check (#361): does the `id`-matched node satisfy
  `filter_conditions`? Returns `{:ok, %Bolty.Response{}}`.
  """
  def node_matching(label, id_props, filter_conditions)
      when (is_atom(label) or is_list(label)) and is_map(id_props) and is_list(filter_conditions) do
    Query.node_matching(label, id_props, filter_conditions)
    |> Cypher.run()
  end

  @doc """
  Bulk destroy (#361): deletes every node of `label` matching `conditions` that
  isn't protected by a preservation `guard`. Returns `{:ok, %Bolty.Response{}}` —
  with captured pre-delete node data when `return?`.
  """
  def bulk_detach_delete(label, conditions, guards, return?)
      when (is_atom(label) or is_list(label)) and is_list(conditions) and is_list(guards) and
             is_boolean(return?) do
    Query.bulk_detach_delete(label, conditions, guards, return?)
    |> Cypher.run()
  end

  @spec merge_node(atom(), map()) ::
          {:error, %{:__exception__ => true, :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, any()}
  @doc """
  Merges a neo4j node with label and properties

  ## Examples
  ```
  iex> {result, _} = AshNeo4j.Neo4jHelper.merge_node(:Actor, %{name: "Bill Nighy", born: 1949})
  iex> result
  :ok
  ```
  """
  def merge_node(label, properties) when is_atom(label) and is_map(properties) do
    Query.merge_node(label, properties)
    |> Cypher.run()
  end

  @spec upsert_node(atom() | [atom()], map(), map(), map(), [atom()]) ::
          {:error, %{:__exception__ => true, :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, any()}
  @doc """
  Atomic upsert (#379): MERGE on `merge_props` (the identity), `ON CREATE SET` the
  rest (`create_props`), `ON MATCH SET` the `set_on_upsert` fields (`match_props`).

  `create_labels` (#392) are extra labels added with `ON CREATE SET n:Label` so an
  upserted node carries the same full label set a plain create writes.
  """
  def upsert_node(label, merge_props, create_props, match_props, create_labels \\ [])
      when (is_atom(label) or is_list(label)) and is_map(merge_props) and is_map(create_props) and
             is_map(match_props) and is_list(create_labels) do
    Query.upsert_node(label, merge_props, create_props, match_props, create_labels)
    |> Cypher.run()
  end

  @spec update_node(atom() | [atom()], map(), map(), list()) ::
          {:error, %{:__exception__ => true, :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, any()}
  @doc """
  Updates neo4j node properties

  ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node([:Actor], %{name: "Bill Nighy"})
  iex> {result, _} = AshNeo4j.Neo4jHelper.update_node(:Actor, %{name: "Bill Nighy"}, %{born: 1949})
  iex> result
  :ok
  ```
  """
  def update_node(label, match_properties, set_properties, remove_properties \\ [], opts \\ [])
      when (is_atom(label) or is_list(label)) and is_map(set_properties) and is_list(opts) do
    Query.update_node(label, match_properties, set_properties, remove_properties, opts)
    |> Cypher.run()
  end

  @spec update_node_labels(atom() | [atom()], map(), [atom()], [atom()]) ::
          {:error, %{:__exception__ => true, :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, any()}
  @doc """
  Adds and/or removes labels on an existing node (matched by label + properties).

  A node's label set drives `AshNeo4j.worlds/1`, so this places a node in — or
  strips it of — a resolvable world. Useful in tests: create a node via Ash,
  then mutate its labels to set up a chosen world (or an unresolvable one).

  ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node([:SRM, :Place], %{name: "Sydney"})
  iex> {result, _} = AshNeo4j.Neo4jHelper.update_node_labels(:Place, %{name: "Sydney"}, [], [:SRM])
  iex> result
  :ok
  ```
  """
  def update_node_labels(label, match_properties, add_labels, remove_labels \\ [])
      when (is_atom(label) or is_list(label)) and is_map(match_properties) and
             is_list(add_labels) and is_list(remove_labels) do
    Query.update_node_labels(label, match_properties, add_labels, remove_labels)
    |> Cypher.run()
  end

  @spec relate_nodes(atom() | [atom()], map(), atom() | [atom()], map(), atom(), atom()) ::
          {:error, %{:__exception__ => true, :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, any()}
  @doc """
  Relates two nodes with a relationship type, merging relationship
    ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node([:Actor], %{name: "Bill Nighy", born: 1949})
  iex> AshNeo4j.Neo4jHelper.create_node([:Movie], %{title: "Love Actually"})
  iex> {result, _} = AshNeo4j.Neo4jHelper.relate_nodes(:Actor, %{name: "Bill Nighy"}, :Movie, %{title: "Love Actually"}, :ACTED_IN, :outgoing)
  iex> result
  :ok
  ```
  """
  def relate_nodes(source_label, source_properties, dest_label, dest_properties, edge_label, edge_direction)
      when (is_atom(source_label) or is_list(source_label)) and is_map(source_properties) and
             (is_atom(dest_label) or is_list(dest_label)) and is_map(dest_properties) and
             is_atom(edge_label) and is_atom(edge_direction) do
    Query.relate(source_label, source_properties, dest_label, dest_properties, edge_label, edge_direction)
    |> Cypher.run()
  end

  @spec unrelate_nodes(atom() | [atom()], map(), atom() | [atom()], map(), atom(), atom(), list()) ::
          {:error, %{:__exception__ => true, :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, any()}
  @doc """
  Unrelates two nodes with a relationship type
    ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node([:Actor], %{name: "Bill Nighy", born: 1949})
  iex> AshNeo4j.Neo4jHelper.create_node([:Movie], %{title: "Love Actually"})
  iex> AshNeo4j.Neo4jHelper.relate_nodes(:Actor, %{name: "Bill Nighy"}, :Movie, %{title: "Love Actually"}, :ACTED_IN, :outgoing)
  iex> {result, _} = AshNeo4j.Neo4jHelper.unrelate_nodes(:Actor, %{name: "Bill Nighy"}, :Movie, %{title: "Love Actually"}, :ACTED_IN, :outgoing)
  iex> result
  :ok
  ```
  """
  def unrelate_nodes(source_label, source_properties, dest_label, dest_properties, edge_label, edge_direction, guard \\ [])
      when (is_atom(source_label) or is_list(source_label)) and is_map(source_properties) and
             is_atom(dest_label) and is_map(dest_properties) and
             is_atom(edge_label) and is_atom(edge_direction) and is_list(guard) do
    Query.unrelate(source_label, source_properties, dest_label, dest_properties, edge_label, edge_direction, guard: guard)
    |> Cypher.run()
  end

  @spec relate_nodes_unrelating_source(atom(), map(), atom(), map(), atom(), atom(), list()) ::
          {:error, %{:__exception__ => true, :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, any()}
  @doc """
  Relates two nodes unrelating the source node from any similar relationships
   ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node([:Fan], %{name: "Matt"})
  iex> AshNeo4j.Neo4jHelper.create_node([:Movie], %{title: "Love Actually"})
  iex> AshNeo4j.Neo4jHelper.create_node([:Movie], %{title: "Bend it Like Beckham"})
  iex> AshNeo4j.Neo4jHelper.relate_nodes(:Fan, %{name: "Matt"}, :Movie, %{title: "Love Actually"}, :FAVOURITE, :outgoing)
  iex> {result, _} = AshNeo4j.Neo4jHelper.relate_nodes_unrelating_source(:Fan, %{name: "Matt"}, :Movie, %{title: "Bend it Like Beckham"}, :FAVOURITE, :outgoing)
  iex> result
  :ok
  ```
  """
  def relate_nodes_unrelating_source(
        source_label,
        source_properties,
        dest_label,
        dest_properties,
        edge_label,
        edge_direction,
        guard \\ []
      )
      when (is_atom(source_label) or is_list(source_label)) and is_map(source_properties) and
             is_atom(dest_label) and is_map(dest_properties) and
             is_atom(edge_label) and is_atom(edge_direction) and is_list(guard) do
    Query.relate_unrelating_source(
      source_label,
      source_properties,
      dest_label,
      dest_properties,
      edge_label,
      edge_direction,
      guard: guard
    )
    |> Cypher.run()
  end

  @spec relate_nodes_unrelating_destination(atom(), map(), atom(), map(), atom(), atom(), list()) ::
          {:error, %{:__exception__ => true, :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, any()}
  @doc """
  Relates two nodes unrelating the destination node from any similar relationships
   ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node([:Fan], %{name: "Matt"})
  iex> AshNeo4j.Neo4jHelper.create_node([:Movie], %{title: "Love Actually"})
  iex> AshNeo4j.Neo4jHelper.create_node([:Movie], %{title: "Bend it Like Beckham"})
  iex> AshNeo4j.Neo4jHelper.relate_nodes(:Fan, %{name: "Matt"}, :Movie, %{title: "Love Actually"}, :FAVOURITE, :outgoing)
  iex> {result, _} = AshNeo4j.Neo4jHelper.relate_nodes_unrelating_destination(:Movie, %{title: "Bend it Like Beckham"}, :Fan, %{name: "Matt"}, :FAVOURITE, :incoming)
  iex> result
  :ok
  ```
  """
  def relate_nodes_unrelating_destination(
        source_label,
        source_properties,
        dest_label,
        dest_properties,
        edge_label,
        edge_direction,
        guard \\ []
      )
      when (is_atom(source_label) or is_list(source_label)) and is_map(source_properties) and
             is_atom(dest_label) and is_map(dest_properties) and
             is_atom(edge_label) and is_atom(edge_direction) and is_list(guard) do
    Query.relate_unrelating_destination(
      source_label,
      source_properties,
      dest_label,
      dest_properties,
      edge_label,
      edge_direction,
      guard: guard
    )
    |> Cypher.run()
  end

  @spec relate_nodes_unrelating_source_and_destination(atom(), map(), atom(), map(), atom(), atom(), list()) ::
          {:error, %{:__exception__ => true, :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, any()}
  @doc """
  Relates two nodes unrelating the source and destination node from any similar relationships
   ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node([:Person], %{name: "Marlo"})
  iex> AshNeo4j.Neo4jHelper.create_node([:Person], %{name: "Harry"})
  iex> AshNeo4j.Neo4jHelper.create_node([:Person], %{name: "Marion"})
  iex> AshNeo4j.Neo4jHelper.create_node([:Person], %{name: "Robin"})
  iex> AshNeo4j.Neo4jHelper.relate_nodes(:Person, %{name: "Marlo"}, :Person, %{name: "Harry"}, :PARTNER, :outgoing)
  iex> AshNeo4j.Neo4jHelper.relate_nodes(:Person, %{name: "Marion"}, :Person, %{name: "Robin"}, :PARTNER, :outgoing)
  iex> {result, _} = AshNeo4j.Neo4jHelper.relate_nodes_unrelating_source_and_destination(:Person, %{name: "Marlo"}, :Person, %{name: "Robin"}, :PARTNER, :outgoing)
  iex> result
  :ok
  ```
  """
  def relate_nodes_unrelating_source_and_destination(
        source_label,
        source_properties,
        dest_label,
        dest_properties,
        edge_label,
        edge_direction,
        guard \\ []
      )
      when (is_atom(source_label) or is_list(source_label)) and is_map(source_properties) and
             is_atom(dest_label) and is_map(dest_properties) and
             is_atom(edge_label) and is_atom(edge_direction) and is_list(guard) do
    Query.relate_unrelating_both(
      source_label,
      source_properties,
      dest_label,
      dest_properties,
      edge_label,
      edge_direction,
      guard: guard
    )
    |> Cypher.run()
  end

  @doc """
  Relates two nodes, honouring exclusivity and an optional `changeset.filter` guard.

  `opts`:
    * `:exclusive` — `{source_exclusive?, destination_exclusive?}` (default `{false, false}`),
      selecting the plain / unrelate-source / unrelate-destination / unrelate-both render.
    * `:guard` — a `changeset.filter` condition list (#368) gating the attach on the
      live source node; a guard miss yields zero rows ⇒ the caller raises `StaleRecord`.
  """
  @spec relate_nodes(atom() | [atom()], map(), atom() | [atom()], map(), atom(), atom(), keyword()) ::
          {:error, %{:__exception__ => true, :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, any()}
  def relate_nodes(source_label, source_properties, dest_label, dest_properties, edge_label, edge_direction, opts)
      when (is_atom(source_label) or is_list(source_label)) and is_map(source_properties) and
             (is_atom(dest_label) or is_list(dest_label)) and is_map(dest_properties) and
             is_atom(edge_label) and is_atom(edge_direction) and is_list(opts) do
    guard = Keyword.get(opts, :guard, [])

    case Keyword.get(opts, :exclusive, {false, false}) do
      {false, false} ->
        Query.relate(source_label, source_properties, dest_label, dest_properties, edge_label, edge_direction, guard: guard)
        |> Cypher.run()

      {true, false} ->
        relate_nodes_unrelating_source(
          source_label,
          source_properties,
          dest_label,
          dest_properties,
          edge_label,
          edge_direction,
          guard
        )

      {false, true} ->
        relate_nodes_unrelating_destination(
          source_label,
          source_properties,
          dest_label,
          dest_properties,
          edge_label,
          edge_direction,
          guard
        )

      {true, true} ->
        relate_nodes_unrelating_source_and_destination(
          source_label,
          source_properties,
          dest_label,
          dest_properties,
          edge_label,
          edge_direction,
          guard
        )
    end
  end

  @spec relate_nodes(atom() | [atom()], map(), list()) ::
          {:error, Exception.t()}
          | :ok
  @doc """
  Creates source neo4j node with label, properties and relationships to existing nodes

  ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node([:Actor], %{title: "Bill Nighy"})
  iex> AshNeo4j.Neo4jHelper.create_node([:Actor], %{title: "Keira Knightley"})
  iex> AshNeo4j.Neo4jHelper.create_node([:Movie], %{title: "Love Actually"})
  iex> AshNeo4j.Neo4jHelper.create_node([:Movie], %{title: "Bend it Like Beckham"})
  iex> AshNeo4j.Neo4jHelper.create_node([:Movie], %{title: "The Immitation Game"})

  iex> :ok = AshNeo4j.Neo4jHelper.relate_nodes(:Actor, %{name: "Bill Nighy"}, [{:Movie, %{title: "Love Actually"}, :ACTED_IN, :outgoing, false}])
  iex> :ok = AshNeo4j.Neo4jHelper.relate_nodes(:Actor, %{name: "Keira Knightley"}, [{:Movie, %{title: "Love Actually"}, :ACTED_IN, :outgoing, false}, {:Movie, %{title: "Bend it Like Beckham"}, :ACTED_IN, :outgoing, false}])
  ```
  """
  def relate_nodes(label, properties, relationships)
      when (is_atom(label) or is_list(label)) and is_map(properties) and is_list(relationships) do
    results =
      Enum.reduce_while(relationships, [], fn {dest_label, dest_properties, edge_label, edge_direction, exclusive},
                                              acc ->
        if exclusive do
          case relate_nodes_unrelating_destination(
                 label,
                 properties,
                 dest_label,
                 dest_properties,
                 edge_label,
                 edge_direction
               ) do
            {:ok, result} -> {:cont, [result | acc]}
            {:error, _} -> {:halt, :error}
          end
        else
          case relate_nodes(label, properties, dest_label, dest_properties, edge_label, edge_direction) do
            {:ok, result} -> {:cont, [result | acc]}
            {:error, _} -> {:halt, :error}
          end
        end
      end)

    case results do
      :error -> {:error, AshNeo4j.Error.Internal.exception(detail: "error relating nodes during create")}
      [] -> {:error, AshNeo4j.Error.Internal.exception(detail: "unexpected empty result relating nodes during create")}
      _ -> :ok
    end
  end

  @spec nodes_relate_how?(atom(), map(), atom(), map(), atom(), atom()) :: :error | false | true
  @doc """
  Tests if two nodes are directly related
    ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node([:Actor], %{name: "Bill Nighy", born: 1949})
  iex> AshNeo4j.Neo4jHelper.create_node([:Movie], %{title: "Love Actually"})
  iex> AshNeo4j.Neo4jHelper.relate_nodes(:Actor, %{name: "Bill Nighy"}, :Movie, %{title: "Love Actually"}, :ACTED_IN, :outgoing)
  iex> AshNeo4j.Neo4jHelper.nodes_relate_how?(:Actor, %{name: "Bill Nighy"}, :Movie, %{title: "Love Actually"}, :ACTED_IN, :outgoing)
  true
  ```
  """
  def nodes_relate_how?(source_label, source_properties, dest_label, dest_properties, edge_label, edge_direction)
      when (is_atom(source_label) or is_list(source_label)) and is_map(source_properties) and
             (is_atom(dest_label) or is_list(dest_label)) and is_map(dest_properties) and
             is_atom(edge_label) and is_atom(edge_direction) do
    {src_pattern, src_params} = Cypher.parameterized_node(:s, List.wrap(source_label), source_properties)
    {dest_pattern, dest_params} = Cypher.parameterized_node(:d, List.wrap(dest_label), dest_properties)

    cypher = "MATCH #{src_pattern}#{Cypher.relationship(:r, edge_label, edge_direction)}#{dest_pattern} RETURN s, r, d"

    case Cypher.run(cypher, Map.merge(src_params, dest_params)) do
      {:ok, %{records: records}} ->
        length(records) > 0

      {:error, error} ->
        Logger.error("AshNeo4j.Neo4jHelper: error running query: #{inspect(error)}")
        :error
    end
  end

  @spec nodes_relate_how?(atom(), map(), atom(), map(), list(tuple())) :: :error | false | true
  @doc """
  Tests if two nodes are related by traversal
    ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node([:Actor], %{name: "Keira Knightley"})
  iex> AshNeo4j.Neo4jHelper.create_node([:Actor], %{name: "Bill Nighy"})
  iex> AshNeo4j.Neo4jHelper.create_node([:Movie], %{title: "Love Actually"})
  iex> AshNeo4j.Neo4jHelper.relate_nodes(:Actor, %{name: "Keira Knightley"}, :Movie, %{title: "Love Actually"}, :ACTED_IN, :outgoing)
  iex> AshNeo4j.Neo4jHelper.relate_nodes(:Actor, %{name: "Bill Nighy"}, :Movie, %{title: "Love Actually"}, :ACTED_IN, :outgoing)
  iex> AshNeo4j.Neo4jHelper.nodes_relate_how?(:Actor, %{name: "Bill Nighy"}, :Actor, %{name: "Keira Knightley"}, [ACTED_IN: :outgoing, ACTED_IN: :incoming])
  true
  ```
  """
  def nodes_relate_how?(source_label, source_properties, dest_label, dest_properties, edges)
      when (is_atom(source_label) or is_list(source_label)) and is_map(source_properties) and
             (is_atom(dest_label) or is_list(dest_label)) and is_map(dest_properties) and
             is_list(edges) do
    {src_pattern, src_params} = Cypher.parameterized_node(:s, List.wrap(source_label), source_properties)
    {dest_pattern, dest_params} = Cypher.parameterized_node(:d, List.wrap(dest_label), dest_properties)

    path =
      Enum.reduce(edges, "", fn {edge_label, edge_direction}, acc ->
        variable = String.to_atom("r#{String.length(acc)}")

        if acc == "",
          do: Cypher.relationship(variable, edge_label, edge_direction),
          else: acc <> "()" <> Cypher.relationship(variable, edge_label, edge_direction)
      end)

    cypher = "MATCH #{src_pattern}#{path}#{dest_pattern} RETURN s, d"

    case Cypher.run(cypher, Map.merge(src_params, dest_params)) do
      {:ok, %{records: records}} ->
        length(records) > 0

      {:error, error} ->
        Logger.error("AshNeo4j.Neo4jHelper: error running query: #{inspect(error)}")
        :error
    end
  end

  @spec read_nodes(atom()) ::
          {:error, %{:__exception__ => true, :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, any()}
  @doc """
  Reads nodes from Neo4j, given label, and optionally properties

  ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node([:Actor], %{name: "Bill Nighy", born: 1949})
  iex> {:ok, %{records: records}} = AshNeo4j.Neo4jHelper.read_nodes(:Actor, %{name: "Bill Nighy"})
  iex> length(records)
  1
  ```
  """
  def read_nodes(label, properties \\ %{}) when (is_atom(label) or is_list(label)) and is_map(properties) do
    Query.match_nodes(label, properties)
    |> Cypher.run()
  end

  @spec read_limited(atom(), nil | integer()) ::
          {:error, %{:__exception__ => true, :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, any()}
  @doc """
  Reads limited nodes from Neo4j, given label, limit and optionally properties

  ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node([:Actor], %{name: "Bill Nighy", born: 1949})
  iex> {:ok, %{records: records}} = AshNeo4j.Neo4jHelper.read_limited(:Actor, 1)
  iex> length(records)
  1
  ```
  """
  def read_limited(label, limit, properties \\ %{}) when is_atom(label) and is_map(properties) do
    Query.match_nodes(label, properties)
    |> Query.add_limit(limit)
    |> Cypher.run()
  end

  @spec read_nodes(atom()) ::
          {:error, %{:__exception__ => true, :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, any()}

  @spec read_nodes_related(any()) :: none()
  @doc """
  Reads nodes from Neo4j, returning any related nodes

  ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node([:Actor], %{name: "Bill Nighy", born: 1949})
  iex> AshNeo4j.Neo4jHelper.create_node([:Movie], %{title: "Love Actually"})
  iex> :ok = AshNeo4j.Neo4jHelper.relate_nodes(:Actor, %{name: "Bill Nighy"}, [{:Movie, %{title: "Love Actually"}, :ACTED_IN, :outgoing, false}])
  iex> {:ok, %{records: records}} = AshNeo4j.Neo4jHelper.read_nodes_related(:Actor, %{name: "Bill Nighy"})
  iex> length(records)
  1
  ```
  """
  def read_nodes_related(label, properties \\ %{}) when (is_atom(label) or is_list(label)) and is_map(properties) do
    Query.node_read_with_properties(label, properties)
    |> Cypher.run()
  end
end
