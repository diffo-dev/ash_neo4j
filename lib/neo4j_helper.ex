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
  Delete neo4j nodes

  ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node(:Movie, %{title: "Love Actually"})
  iex> AshNeo4j.Neo4jHelper.create_node(:Movie, %{title: "Bend it Like Beckham"})
  iex> AshNeo4j.Neo4jHelper.create_node_with_relationships(:Actor, %{name: "Keira Knightley"}, [{:Movie, %{title: "Love Actually"}, :ACTED_IN, :outgoing}, {:Movie, %{title: "Bend it Like Beckham"}, :ACTED_IN, :outgoing}])
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
       ", " <>
       Cypher.node(:d, dest_label, dest_properties) <>
       " MERGE (s)" <> Cypher.relationship(:r, edge_label, edge_direction) <> "(d) RETURN s, r, d")
    |> Cypher.run()
  end

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

  @doc """
  Creates source neo4j node with label, properties and relationship to an existing node

  ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node(:Movie, %{title: "Love Actually"})
  iex> {result, _} = AshNeo4j.Neo4jHelper.create_node_with_relationship(:Actor, %{name: "Keira Knightley"}, :Movie, %{title: "Love Actually"}, :ACTED_IN, :outgoing)
  iex> result
  :ok
  ```
  """
  # MATCH (d:Movie {title: "Love Actually"}) CREATE (s:Actor {name: "Keira Knightley"}) -[r:ACTED_IN]->(d) RETURN s, r, d
  def create_node_with_relationship(label, properties, dest_label, dest_properties, edge_label, edge_direction)
      when is_atom(label) do
    dest_node = Cypher.node(:d, dest_label, dest_properties)

    ("MATCH " <>
       dest_node <>
       " CREATE " <>
       Cypher.node(:s, label, properties) <>
       Cypher.relationship(:r, edge_label, edge_direction) <>
       " (d) RETURN s, r, d")
    |> Cypher.run()
  end

  @doc """
  Creates source neo4j node with label, properties and relationships to existing nodes

  ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node(:Movie, %{title: "Love Actually"})
  iex> AshNeo4j.Neo4jHelper.create_node(:Movie, %{title: "Bend it Like Beckham"})
  iex> {result, _} = AshNeo4j.Neo4jHelper.create_node_with_relationships(:Actor, %{name: "Bill Nighy"}, [{:Movie, %{title: "Love Actually"}, :ACTED_IN, :outgoing}])
  iex> result
  :ok
  iex> {result, _} = AshNeo4j.Neo4jHelper.create_node_with_relationships(:Actor, %{name: "Keira Knightley"}, [{:Movie, %{title: "Love Actually"}, :ACTED_IN, :outgoing}, {:Movie, %{title: "Bend it Like Beckham"}, :ACTED_IN, :outgoing}])
  iex> result
  :ok
  ```
  """
  # MATCH (d1:Movie {title: "Love Actually"}), (d2:Movie {title: "Bend it Like Beckham"}) CREATE (s:Actor {name: "Keira Knightley"}) -[r1:ACTED_IN]->(d1) MERGE (s) -[r2:ACTED_IN]->(d2) RETURN s, r1, d1, r2, d2
  def create_node_with_relationships(label, properties, relationships)
      when is_atom(label) and is_map(properties) and is_list(relationships) do
    case length(relationships) do
      0 ->
        create_node(label, properties)

      1 ->
        {dest_label, dest_properties, edge_label, edge_direction} = hd(relationships)
        create_node_with_relationship(label, properties, dest_label, dest_properties, edge_label, edge_direction)

      _ ->
        match =
          Enum.reduce(relationships, [], fn relationship, acc ->
            {dest_label, dest_properties, _edge_label, _edge_direction} = relationship
            i = length(acc)
            node = String.to_atom("d#{i}")
            [Cypher.node(node, dest_label, dest_properties) | acc]
          end)
          |> Enum.join(", ")

        {_dest_label, _dest_properties, edge_label, edge_direction} = hd(relationships)

        create = Cypher.node(:s, label, properties) <> Cypher.relationship(:r0, edge_label, edge_direction) <> "(d0)"

        merge =
          Enum.reduce(tl(relationships), [], fn relationship, acc ->
            {_dest_label, _dest_properties, edge_label, edge_direction} = relationship
            i = length(acc) + 1
            edge = String.to_atom("r#{i}")
            ["(s)" <> Cypher.relationship(edge, edge_label, edge_direction) <> "(d#{i})" | acc]
          end)
          |> Enum.join(", ")

        ret =
          Enum.reduce(relationships, [], fn _relationship, acc ->
            i = length(acc)
            ["r#{i}, d#{i}" | acc]
          end)
          |> Enum.join(", ")

        ("MATCH " <>
           match <>
           " CREATE " <>
           create <>
           " MERGE " <>
           merge <>
           " RETURN s, " <> ret)
        |> Cypher.run()
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
end
