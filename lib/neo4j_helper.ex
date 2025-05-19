defmodule AshNeo4j.Neo4jHelper do

  alias AshNeo4j.Cypher

  @moduledoc """
  AshNeo4j DataLayer Neo4j Helper
  """


  @doc """
  Creates a neo4j node with label and properties

  ## Examples
  ```
  iex> {result, _} = AshNeo4j.Neo4jHelper.create_node(:Actor, %{name: "Bill Nighy"})
  iex> result
  :ok
  ```
  """
  def create_node(label, properties) when is_atom(label) do
    "CREATE " <> Cypher.node(:n, label, properties) <> " RETURN n"
    |> Cypher.run()
  end

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

  @doc """
  Delete neo4j nodes

  ## Examples
  ```
  iex> {result, _} = AshNeo4j.Neo4jHelper.delete_nodes(:Post)
  iex> result
  :ok
  ```
  """
  def delete_nodes(label) when is_atom(label) do
    "MATCH " <> Cypher.node(:n, label) <> " DETACH DELETE n"
    |> Cypher.run()
  end

  @doc """
  Merges a neo4j node with label and properties

  ## Examples
  ```
  iex> {result, _} = AshNeo4j.Neo4jHelper.merge_node(:Actor, %{name: "Bill Nighy", born: 1949})
  iex> result
  :ok
  ```
  """
  def merge_node(label, properties) when is_atom(label) do
    "MERGE " <> Cypher.node(:n, label, properties) <> " RETURN n"
    |> Cypher.run()
  end

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
  def update_node(label, match_properties, set_properties) when is_atom(label) do
    IO.inspect(match_properties, label: :update_node_match_properties)
    IO.inspect(set_properties, label: :update_node_set_properties)
    "MATCH " <> Cypher.node(:n, label, match_properties) <> " SET n += " <> Cypher.properties(set_properties) <> " RETURN n"
    |> IO.inspect(label: :update_node_cypher)
    |> Cypher.run() |> IO.inspect(label: :update_node_cypher_result)
  end

  @doc """
  Relates two nodes with a relationship type
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
    when is_atom(source_label) and is_map(source_properties) and is_atom(dest_label) and is_map(dest_properties) and is_atom(edge_label) and is_atom(edge_direction) do
    "MATCH " <> Cypher.node(:s, source_label, source_properties) <> " MATCH " <> Cypher.node(:d, dest_label, dest_properties) <>
      " CREATE (s)" <> Cypher.relationship(:r, edge_label, edge_direction) <> "(d) RETURN s, r, d"
    |> Cypher.run()
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
  when is_atom(source_label) and is_map(source_properties) and is_atom(dest_label) and is_map(dest_properties) and is_atom(edge_label) and is_atom(edge_direction) do
    cypher = "MATCH "<> Cypher.node(:s, source_label, source_properties) <> Cypher.relationship(:r, edge_label, edge_direction) <> Cypher.node(:d, dest_label, dest_properties) <> " RETURN s, r, d"
    case Cypher.run(cypher) do
      {:ok, %{records: records}} ->
        length(records) > 0
      {:error, error} ->
        IO.puts("Error running query: #{inspect(error)}")
        :error
    end
  end

  @doc """
  Reads nodes from Neo4j, given label and optionally properties

  ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node(:Actor, %{name: "Bill Nighy", born: 1949})
  iex> {:ok, %{records: records}} = AshNeo4j.Neo4jHelper.read_nodes(:Actor, %{name: "Bill Nighy"})
  iex> length(records)
  1
  ```
  """
  def read_nodes(label, properties \\ %{}) when is_atom(label) and is_map(properties) do
    "MATCH " <> Cypher.node(:n, label, properties) <> " RETURN n"
    |> Cypher.run()
  end
end
