# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Neo4jHelper do
  require Logger
  alias AshNeo4j.Cypher

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
    {node_cypher, parameters} = Cypher.parameterized_node(:n, labels, properties)

    ("CREATE " <> node_cypher <> " RETURN n")
    |> Cypher.run(parameters)
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
    "MATCH (n) DETACH DELETE n"
    |> Cypher.run()
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
  def delete_nodes(label, properties \\ %{})
      when is_atom(label) and is_map(properties) do
    {node_cypher, parameters} = Cypher.parameterized_node(:n, [label], properties)

    ("MATCH " <>
       node_cypher <>
       " DETACH DELETE n")
    |> Cypher.run(parameters)
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
  def safe_delete_nodes(label, properties, relationships)
      when is_atom(label) and length(relationships) != 0 do
    node_relationships =
      Enum.map_join(relationships, " AND NOT ", fn {edge_label, edge_direction, dest_label} ->
        case edge_direction do
          :incoming ->
            "(n)<-[:#{edge_label}]-(:#{dest_label})"

          :outgoing ->
            "(n)-[:#{edge_label}]->(:#{dest_label})"

          _ ->
            "(n)-[:#{edge_label}]-(:#{dest_label})"
        end
      end)

    {node_cypher, parameters} = Cypher.parameterized_node(:n, [label], properties)

    ("MATCH " <>
       node_cypher <>
       " WHERE NOT " <>
       node_relationships <>
       " DETACH DELETE n")
    |> Cypher.run_expecting_deletions(parameters)
  end

  def safe_delete_nodes(label, properties, relationships)
      when is_atom(label) and length(relationships) == 0 do
    delete_nodes(label, properties)
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
  def merge_node(label, properties)
      when is_atom(label) and is_map(properties) do
    {node_cypher, parameters} = Cypher.parameterized_node(:n, [label], properties)

    ("MERGE " <> node_cypher <> " RETURN n")
    |> Cypher.run(parameters)
  end

  @spec update_node(atom(), map(), map(), list()) ::
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
  def update_node(label, match_properties, set_properties, remove_properties \\ [])

  def update_node(label, match_properties, set_properties, [])
      when is_atom(label) and is_map(set_properties) do
    {node_cypher, parameters} = Cypher.parameterized_node(:n, [label], match_properties)
    {set_properties_cypher, set_parameters} = Cypher.parameterized_properties(:n, set_properties)

    ("MATCH " <>
       node_cypher <>
       " SET n += " <>
       set_properties_cypher <>
       " RETURN n")
    |> Cypher.run(Map.merge(parameters, set_parameters))
  end

  def update_node(label, match_properties, set_properties, remove_properties)
      when is_atom(label) and map_size(set_properties) == 0 do
    {node_cypher, parameters} = Cypher.parameterized_node(:n, [label], match_properties)
    remove_properties_cypher = Cypher.remove_properties(:n, remove_properties)

    ("MATCH " <>
       node_cypher <>
       " REMOVE " <>
       remove_properties_cypher <>
       " RETURN n")
    |> Cypher.run(parameters)
  end

  def update_node(label, match_properties, set_properties, remove_properties)
      when is_atom(label) and map_size(set_properties) != 0 and length(remove_properties) != 0 do
    {node_cypher, parameters} = Cypher.parameterized_node(:n, [label], match_properties)
    {set_properties_cypher, set_parameters} = Cypher.parameterized_properties(:n, set_properties)
    remove_properties_cypher = Cypher.remove_properties(:n, remove_properties)

    ("MATCH " <>
       node_cypher <>
       " SET n += " <>
       set_properties_cypher <>
       " REMOVE " <>
       remove_properties_cypher <>
       " RETURN n")
    |> Cypher.run(Map.merge(parameters, set_parameters))
  end

  @spec relate_nodes(atom(), map(), atom(), map(), atom(), atom()) ::
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
      when is_atom(source_label) and is_map(source_properties) and is_atom(dest_label) and is_map(dest_properties) and
             is_atom(edge_label) and is_atom(edge_direction) do
    {source_node_cypher, source_parameters} = Cypher.parameterized_node(:s, [source_label], source_properties)
    {dest_node_cypher, dest_parameters} = Cypher.parameterized_node(:d, [dest_label], dest_properties)

    ("MATCH " <>
       source_node_cypher <>
       " OPTIONAL MATCH " <>
       dest_node_cypher <>
       " MERGE (s)" <>
       Cypher.relationship(:r, edge_label, edge_direction) <>
       "(d) RETURN s, r, d")
    |> Cypher.run(Map.merge(source_parameters, dest_parameters))
  end

  @spec unrelate_nodes(atom(), map(), atom(), map(), atom(), atom()) ::
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
  def unrelate_nodes(source_label, source_properties, dest_label, dest_properties, edge_label, edge_direction)
      when is_atom(source_label) and is_map(source_properties) and is_atom(dest_label) and is_map(dest_properties) and
             is_atom(edge_label) and is_atom(edge_direction) do
    {source_node_cypher, source_parameters} = Cypher.parameterized_node(:s, [source_label], source_properties)
    {dest_node_cypher, dest_parameters} = Cypher.parameterized_node(:d, [dest_label], dest_properties)

    ("MATCH " <>
       source_node_cypher <>
       " " <>
       Cypher.relationship(:r, edge_label, edge_direction) <>
       dest_node_cypher <>
       " DELETE r RETURN s, d")
    |> Cypher.run(Map.merge(source_parameters, dest_parameters))
  end

  @spec relate_nodes_unrelating_source(atom(), map(), atom(), map(), atom(), atom()) ::
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
        edge_direction
      )
      when is_atom(source_label) and is_map(source_properties) and is_atom(dest_label) and is_map(dest_properties) and
             is_atom(edge_label) and is_atom(edge_direction) do
    {source_node_cypher, source_parameters} = Cypher.parameterized_node(:s, [source_label], source_properties)
    {dest_node_cypher, dest_parameters} = Cypher.parameterized_node(:d, [dest_label], dest_properties)

    ("MATCH " <>
       source_node_cypher <>
       " WITH s OPTIONAL MATCH (s)" <>
       Cypher.relationship(:r0, edge_label, edge_direction) <>
       Cypher.node(:d0, [dest_label]) <>
       " DELETE r0 WITH s MATCH " <>
       dest_node_cypher <>
       " MERGE (s)" <> Cypher.relationship(:r, edge_label, edge_direction) <> "(d) RETURN s, r, d")
    |> Cypher.run(Map.merge(source_parameters, dest_parameters))
  end

  @spec relate_nodes_unrelating_destination(atom(), map(), atom(), map(), atom(), atom()) ::
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
        edge_direction
      )
      when is_atom(source_label) and is_map(source_properties) and is_atom(dest_label) and is_map(dest_properties) and
             is_atom(edge_label) and is_atom(edge_direction) do
    # cypher is a bit verbose but attempts to not delete/replace existing relationship while avoiding cartesian product
    # "MATCH (s:Movie {title: 'Bend it Like Beckham'}) WITH s OPTIONAL MATCH (s0:Movie) <-[r0:FAVOURITE]-(d:Fan {name: 'Matt'}) WHERE s0 <> s DELETE r0 WITH s, d MERGE (s)<-[r:FAVOURITE]-(d:Fan {name: 'Matt'} RETURN s, r, d"
    {source_node_cypher, source_parameters} = Cypher.parameterized_node(:s, [source_label], source_properties)
    {dest_node_cypher, dest_parameters} = Cypher.parameterized_node(:d, [dest_label], dest_properties)

    ("MATCH " <>
       source_node_cypher <>
       " OPTIONAL MATCH " <>
       dest_node_cypher <>
       " WITH s, d OPTIONAL MATCH " <>
       Cypher.node(:s0, [source_label]) <>
       Cypher.relationship(:r0, edge_label, edge_direction) <>
       " (d) WHERE s0 <> s DELETE r0 WITH s, d MERGE (s)" <>
       Cypher.relationship(:r, edge_label, edge_direction) <>
       "(d) RETURN s, r, d")
    |> Cypher.run(Map.merge(source_parameters, dest_parameters))
  end

  @spec relate_nodes_unrelating_source_and_destination(atom(), map(), atom(), map(), atom(), atom()) ::
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
        edge_direction
      )
      when is_atom(source_label) and is_map(source_properties) and is_atom(dest_label) and is_map(dest_properties) and
             is_atom(edge_label) and is_atom(edge_direction) do
    {source_node_cypher, source_parameters} = Cypher.parameterized_node(:s, [source_label], source_properties)
    {dest_node_cypher, dest_parameters} = Cypher.parameterized_node(:d, [dest_label], dest_properties)

    ("MATCH " <>
       source_node_cypher <>
       " WITH s OPTIONAL MATCH (s)" <>
       Cypher.relationship(:r0, edge_label, edge_direction) <>
       dest_node_cypher <>
       " DELETE r0 WITH s OPTIONAL MATCH " <>
       dest_node_cypher <>
       " WITH s, d OPTIONAL MATCH " <>
       Cypher.node(:s0, [source_label]) <>
       Cypher.relationship(:r0, edge_label, edge_direction) <>
       " (d) WHERE s0 <> s DELETE r0 WITH s, d MERGE (s)" <>
       Cypher.relationship(:r, edge_label, edge_direction) <>
       "(d) RETURN s, r, d")
    |> Cypher.run(Map.merge(source_parameters, dest_parameters))
  end

  def relate_nodes(
        source_label,
        source_properties,
        dest_label,
        dest_properties,
        edge_label,
        edge_direction,
        options
      )
      when is_atom(source_label) and is_map(source_properties) and is_atom(dest_label) and is_map(dest_properties) and
             is_atom(edge_label) and is_atom(edge_direction) and is_tuple(options) do
    case options do
      {false, false} ->
        relate_nodes(
          source_label,
          source_properties,
          dest_label,
          dest_properties,
          edge_label,
          edge_direction
        )

      {true, false} ->
        relate_nodes_unrelating_source(
          source_label,
          source_properties,
          dest_label,
          dest_properties,
          edge_label,
          edge_direction
        )

      {false, true} ->
        relate_nodes_unrelating_destination(
          source_label,
          source_properties,
          dest_label,
          dest_properties,
          edge_label,
          edge_direction
        )

      {true, true} ->
        relate_nodes_unrelating_source_and_destination(
          source_label,
          source_properties,
          dest_label,
          dest_properties,
          edge_label,
          edge_direction
        )
    end
  end

  @spec relate_nodes(atom(), map(), list()) ::
          {:error, bitstring()}
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
      when is_atom(label) and is_map(properties) and is_list(relationships) do
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
            {:ok, result} ->
              {:cont, [result, acc]}

            {:error, _error} ->
              {:halt, :error}
          end
        else
          case relate_nodes(label, properties, dest_label, dest_properties, edge_label, edge_direction) do
            {:ok, result} ->
              {:cont, [result, acc]}

            {:error, _error} ->
              {:halt, :error}
          end
        end
      end)

    case results do
      :error ->
        {:error, "error relating nodes"}

      [] ->
        {:error, "unexpected empty result relating nodes"}

      _ ->
        :ok
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
      when is_atom(source_label) and is_map(source_properties) and is_atom(dest_label) and is_map(dest_properties) and
             is_atom(edge_label) and is_atom(edge_direction) do
    {source_node_cypher, source_parameters} = Cypher.parameterized_node(:s, [source_label], source_properties)
    {dest_node_cypher, dest_parameters} = Cypher.parameterized_node(:d, [dest_label], dest_properties)

    cypher =
      "MATCH " <>
        source_node_cypher <>
        Cypher.relationship(:r, edge_label, edge_direction) <>
        dest_node_cypher <> " RETURN s, r, d"

    case Cypher.run(cypher, Map.merge(source_parameters, dest_parameters)) do
      {:ok, %{records: records}} ->
        length(records) > 0

      {:error, error} ->
        Logger.error("AshNeo4j.Neo4jHelper.Error running query: #{inspect(error)}")
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
      when is_atom(source_label) and is_map(source_properties) and is_atom(dest_label) and is_map(dest_properties) and
             is_list(edges) do
    {source_node_cypher, source_parameters} = Cypher.parameterized_node(:s, [source_label], source_properties)
    {dest_node_cypher, dest_parameters} = Cypher.parameterized_node(:d, [dest_label], dest_properties)

    cypher =
      "MATCH " <>
        source_node_cypher <>
        Enum.reduce(edges, "", fn {edge_label, edge_direction}, acc ->
          variable = String.to_atom("r#{String.length(acc)}")

          if acc == "" do
            acc <> Cypher.relationship(variable, edge_label, edge_direction)
          else
            acc <> "()" <> Cypher.relationship(variable, edge_label, edge_direction)
          end
        end) <>
        dest_node_cypher <> " RETURN s, d"

    case Cypher.run(cypher, Map.merge(source_parameters, dest_parameters)) do
      {:ok, %{records: records}} ->
        length(records) > 0

      {:error, error} ->
        Logger.error("AshNeo4j.Neo4jHelper.Error running query: #{inspect(error)}")
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
  def read_nodes(label, properties \\ %{}) when is_atom(label) and is_map(properties) do
    {node_cypher, parameters} = Cypher.parameterized_node(:n, [label], properties)

    ("MATCH " <> node_cypher <> " RETURN n")
    |> Cypher.run(parameters)
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
    {node_cypher, parameters} = Cypher.parameterized_node(:n, [label], properties)

    case limit do
      nil ->
        "MATCH " <> node_cypher <> " RETURN n"

      _ ->
        "MATCH " <> node_cypher <> " RETURN n LIMIT #{limit}"
    end
    |> Cypher.run(parameters)
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
  def read_nodes_related(label, properties \\ %{}) when is_atom(label) and is_map(properties) do
    {node_cypher, parameters} = Cypher.parameterized_node(:s, [label], properties)

    ("MATCH " <> node_cypher <> " OPTIONAL MATCH (s)-[r]-(d) RETURN s, r, d")
    |> Cypher.run(parameters)
  end
end
