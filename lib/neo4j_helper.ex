defmodule AshNeo4j.Neo4jHelper do
  require Logger
  alias AshNeo4j.Cypher

  @moduledoc """
  AshNeo4j DataLayer Neo4j Helper
  """

  @spec create_node(atom(), map()) ::
          {:error, %{:__exception__ => true, :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, any()}
  @doc """
  Creates a neo4j node with label and properties

  ## Examples
  ```
  iex> {result, _} = AshNeo4j.Neo4jHelper.create_node(:Actor, %{name: "Bill Nighy"})
  iex> result
  :ok
  ```
  """
  def create_node(label, properties) when is_atom(label) and is_map(properties) do
    ("CREATE " <> Cypher.node(:n, label, properties) <> " RETURN n")
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
  iex> AshNeo4j.Neo4jHelper.create_node(:Actor, %{name: "Bill Nighy"})
  iex> {result, _} = AshNeo4j.Neo4jHelper.delete_nodes(:Actor, %{name: "Bill Nighy"})
  iex> result
  :ok
  ```
  """
  def delete_nodes(label, properties \\ %{})
      when is_atom(label) and is_map(properties) do
    ("MATCH " <> Cypher.node(:n, label, properties) <> " DETACH DELETE n")
    |> Cypher.run()
  end

  @doc """
  Safely delete neo4j nodes, delete is guarded by relationships

  ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node(:Actor, %{name: "Keira Knightley"})
  iex> AshNeo4j.Neo4jHelper.create_node(:Movie, %{title: "Love Actually"})
  iex> AshNeo4j.Neo4jHelper.create_node(:Movie, %{title: "Bend it Like Beckham"})
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

    ("MATCH " <>
       Cypher.node(:n, label, properties) <>
       " WHERE NOT " <>
       node_relationships <>
       " DETACH DELETE n")
    |> Cypher.run_expecting_deletions()
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
    ("MERGE " <> Cypher.node(:n, label, properties) <> " RETURN n")
    |> Cypher.run()
  end

  @spec update_node(atom(), map(), map(), list()) ::
          {:error, %{:__exception__ => true, :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, any()}
  @doc """
  Updates neo4j node properties

  ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node(:Actor, %{name: "Bill Nighy"})
  iex> {result, _} = AshNeo4j.Neo4jHelper.update_node(:Actor, %{name: "Bill Nighy"}, %{born: 1949})
  iex> result
  :ok
  ```
  """
  def update_node(label, match_properties, set_properties, remove_properties \\ [])

  def update_node(label, match_properties, set_properties, remove_properties)
      when is_atom(label) and length(remove_properties) == 0 do
    ("MATCH " <>
       Cypher.node(:n, label, match_properties) <> " SET n += " <> Cypher.properties(set_properties) <> " RETURN n")
    |> Cypher.run()
  end

  def update_node(label, match_properties, set_properties, remove_properties)
      when is_atom(label) and map_size(set_properties) == 0 do
    ("MATCH " <>
       Cypher.node(:n, label, match_properties) <>
       " REMOVE " <>
       Cypher.remove_properties(:n, remove_properties) <>
       " RETURN n")
    |> Cypher.run()
  end

  def update_node(label, match_properties, set_properties, remove_properties)
      when is_atom(label) and map_size(set_properties) != 0 and length(remove_properties) != 0 do
    ("MATCH " <>
       Cypher.node(:n, label, match_properties) <>
       " SET n += " <>
       Cypher.properties(set_properties) <>
       " REMOVE " <> Cypher.remove_properties(:n, remove_properties) <> " RETURN n")
    |> Cypher.run()
  end

  @spec relate_nodes(atom(), map(), atom(), map(), atom(), atom()) ::
          {:error, %{:__exception__ => true, :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, any()}
  @doc """
  Relates two nodes with a relationship type, merging relationship
    ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node(:Actor, %{name: "Bill Nighy", born: 1949})
  iex> AshNeo4j.Neo4jHelper.create_node(:Movie, %{title: "Love Actually"})
  iex> {result, _} = AshNeo4j.Neo4jHelper.relate_nodes(:Actor, %{name: "Bill Nighy"}, :Movie, %{title: "Love Actually"}, :ACTED_IN, :outgoing)
  iex> result
  :ok
  ```
  """
  def relate_nodes(source_label, source_properties, dest_label, dest_properties, edge_label, edge_direction)
      when is_atom(source_label) and is_map(source_properties) and is_atom(dest_label) and is_map(dest_properties) and
             is_atom(edge_label) and is_atom(edge_direction) do
    ("MATCH " <>
       Cypher.node(:s, source_label, source_properties) <>
       " OPTIONAL MATCH " <>
       Cypher.node(:d, dest_label, dest_properties) <>
       " MERGE (s)" <> Cypher.relationship(:r, edge_label, edge_direction) <> "(d) RETURN s, r, d")
    |> Cypher.run()
  end

  @spec unrelate_nodes(atom(), map(), atom(), map(), atom(), atom()) ::
          {:error, %{:__exception__ => true, :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, any()}
  @doc """
  Unrelates two nodes with a relationship type
    ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node(:Actor, %{name: "Bill Nighy", born: 1949})
  iex> AshNeo4j.Neo4jHelper.create_node(:Movie, %{title: "Love Actually"})
  iex> AshNeo4j.Neo4jHelper.relate_nodes(:Actor, %{name: "Bill Nighy"}, :Movie, %{title: "Love Actually"}, :ACTED_IN, :outgoing)
  iex> {result, _} = AshNeo4j.Neo4jHelper.unrelate_nodes(:Actor, %{name: "Bill Nighy"}, :Movie, %{title: "Love Actually"}, :ACTED_IN, :outgoing)
  iex> result
  :ok
  ```
  """
  def unrelate_nodes(source_label, source_properties, dest_label, dest_properties, edge_label, edge_direction)
      when is_atom(source_label) and is_map(source_properties) and is_atom(dest_label) and is_map(dest_properties) and
             is_atom(edge_label) and is_atom(edge_direction) do
    ("MATCH " <>
       Cypher.node(:s, source_label, source_properties) <>
       Cypher.relationship(:r, edge_label, edge_direction) <>
       Cypher.node(:d, dest_label, dest_properties) <>
       " DELETE r RETURN s, d")
    |> Cypher.run()
  end

  @spec relate_nodes_unrelating_source(atom(), map(), atom(), map(), atom(), atom()) ::
          {:error, %{:__exception__ => true, :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, any()}
  @doc """
  Relates two nodes unrelating the source node from any similar relationships
   ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node(:Fan, %{name: "Matt"})
  iex> AshNeo4j.Neo4jHelper.create_node(:Movie, %{title: "Love Actually"})
  iex> AshNeo4j.Neo4jHelper.create_node(:Movie, %{title: "Bend it Like Beckham"})
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
    ("MATCH " <>
       Cypher.node(:s, source_label, source_properties) <>
       " WITH s OPTIONAL MATCH (s)" <>
       Cypher.relationship(:r0, edge_label, edge_direction) <>
       Cypher.node(:d0, dest_label, %{}) <>
       " DELETE r0 WITH s MATCH " <>
       Cypher.node(:d, dest_label, dest_properties) <>
       " MERGE (s)" <> Cypher.relationship(:r, edge_label, edge_direction) <> "(d) RETURN s, r, d")
    |> Cypher.run()
  end

  @spec relate_nodes_unrelating_destination(atom(), map(), atom(), map(), atom(), atom()) ::
          {:error, %{:__exception__ => true, :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, any()}
  @doc """
  Relates two nodes unrelating the destination node from any similar relationships
   ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node(:Fan, %{name: "Matt"})
  iex> AshNeo4j.Neo4jHelper.create_node(:Movie, %{title: "Love Actually"})
  iex> AshNeo4j.Neo4jHelper.create_node(:Movie, %{title: "Bend it Like Beckham"})
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
    ("MATCH " <>
       Cypher.node(:s, source_label, source_properties) <>
       " OPTIONAL MATCH " <>
       Cypher.node(:d, dest_label, dest_properties) <>
       " WITH s, d OPTIONAL MATCH " <>
       Cypher.node(:s0, source_label, %{}) <>
       Cypher.relationship(:r0, edge_label, edge_direction) <>
       " (d) WHERE s0 <> s DELETE r0 WITH s, d MERGE (s)" <>
       Cypher.relationship(:r, edge_label, edge_direction) <>
       "(d) RETURN s, r, d")
    |> Cypher.run()
  end

  @spec relate_nodes(atom(), map(), list()) ::
          {:error, bitstring()}
          | :ok
  @doc """
  Creates source neo4j node with label, properties and relationships to existing nodes

  ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node(:Actor, %{title: "Bill Nighy"})
  iex> AshNeo4j.Neo4jHelper.create_node(:Actor, %{title: "Keira Knightley"})
  iex> AshNeo4j.Neo4jHelper.create_node(:Movie, %{title: "Love Actually"})
  iex> AshNeo4j.Neo4jHelper.create_node(:Movie, %{title: "Bend it Like Beckham"})
  iex> AshNeo4j.Neo4jHelper.create_node(:Movie, %{title: "The Immitation Game"})

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
  Tests if two nodes are related with a relationship type
    ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node(:Actor, %{name: "Bill Nighy", born: 1949})
  iex> AshNeo4j.Neo4jHelper.create_node(:Movie, %{title: "Love Actually"})
  iex> AshNeo4j.Neo4jHelper.relate_nodes(:Actor, %{name: "Bill Nighy"}, :Movie, %{title: "Love Actually"}, :ACTED_IN, :outgoing)
  iex> AshNeo4j.Neo4jHelper.nodes_relate_how?(:Actor, %{name: "Bill Nighy"}, :Movie, %{title: "Love Actually"}, :ACTED_IN, :outgoing)
  true
  ```
  """
  def nodes_relate_how?(source_label, source_properties, dest_label, dest_properties, edge_label, edge_direction)
      when is_atom(source_label) and is_map(source_properties) and is_atom(dest_label) and is_map(dest_properties) and
             is_atom(edge_label) and is_atom(edge_direction) do
    cypher =
      "MATCH " <>
        Cypher.node(:s, source_label, source_properties) <>
        Cypher.relationship(:r, edge_label, edge_direction) <>
        Cypher.node(:d, dest_label, dest_properties) <> " RETURN s, r, d"

    case Cypher.run(cypher) do
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
  iex> AshNeo4j.Neo4jHelper.create_node(:Actor, %{name: "Bill Nighy", born: 1949})
  iex> {:ok, %{records: records}} = AshNeo4j.Neo4jHelper.read_nodes(:Actor, %{name: "Bill Nighy"})
  iex> length(records)
  1
  ```
  """
  def read_nodes(label, properties \\ %{}) when is_atom(label) and is_map(properties) do
    ("MATCH " <> Cypher.node(:n, label, properties) <> " RETURN n")
    |> Cypher.run()
  end

  @spec read_limited(atom(), nil | integer()) ::
          {:error, %{:__exception__ => true, :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, any()}
  @doc """
  Reads limited nodes from Neo4j, given label, limit and optionally properties

  ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node(:Actor, %{name: "Bill Nighy", born: 1949})
  iex> {:ok, %{records: records}} = AshNeo4j.Neo4jHelper.read_limited(:Actor, 1)
  iex> length(records)
  1
  ```
  """
  def read_limited(label, limit, properties \\ %{}) when is_atom(label) and is_map(properties) do
    case limit do
      nil ->
        "MATCH " <> Cypher.node(:n, label, properties) <> " RETURN n"

      _ ->
        "MATCH " <> Cypher.node(:n, label) <> " RETURN n LIMIT #{limit}"
    end
    |> Cypher.run()
  end

  @spec read_nodes(atom()) ::
          {:error, %{:__exception__ => true, :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, any()}

  @doc """
  Reads nodes from Neo4j, returning any related nodes

  ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node(:Actor, %{name: "Bill Nighy", born: 1949})
  iex> AshNeo4j.Neo4jHelper.create_node(:Movie, %{title: "Love Actually"})
  iex> :ok = AshNeo4j.Neo4jHelper.relate_nodes(:Actor, %{name: "Bill Nighy"}, [{:Movie, %{title: "Love Actually"}, :ACTED_IN, :outgoing, false}])
  iex> {:ok, %{records: records}} = AshNeo4j.Neo4jHelper.read_nodes_related(:Actor, %{name: "Bill Nighy"})
  iex> length(records)
  1
  ```
  """
  def read_nodes_related(label, properties \\ %{}) when is_atom(label) and is_map(properties) do
    ("MATCH " <> Cypher.node(:s, label, properties) <> " OPTIONAL MATCH (s)-[r]-(d) RETURN s, r, d")
    |> Cypher.run()
  end
end
