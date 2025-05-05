defmodule AshNeo4j.Neo4jHelper do

  alias AshNeo4j.Cypher

  @moduledoc """
  AshNeo4j Datalayer Neo4j Helper
  """

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
    |> Cypher.run_cypher()
  end

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
    "CREATE (n:#{to_string(label)} #{Cypher.cypher_properties(properties)}) RETURN n"
    |> Cypher.run_cypher()
  end

  @doc """
  Creates a neo4j node with label and properties

  ## Examples
  ```
  iex> {result, _} = AshNeo4j.Neo4jHelper.merge_node(:Actor, %{name: "Bill Nighy", born: 1949})
  iex> result
  :ok
  ```
  """
  def merge_node(label, properties) when is_atom(label) do
    "MERGE (n:#{to_string(label)} #{Cypher.cypher_properties(properties)}) RETURN n"
    |> Cypher.run_cypher()
  end

  @spec relate_nodes(atom(), map(), atom(), map(), any()) :: term()
  @doc """
  Relates two nodes with a relationship type
    ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node(:Actor, %{name: "Bill Nighy", born: 1949})
  iex> AshNeo4j.Neo4jHelper.create_node(:Movie, %{title: "Love Actually"})
  iex> {result, _} = AshNeo4j.Neo4jHelper.relate_nodes(:Actor, %{name: "Bill Nighy"}, :Movie, %{title: "Love Actually"}, :ACTED_IN)
  iex> result
  :ok
  ```
  """
  def relate_nodes(source_label, source_properties, dest_label, dest_properties, relationship) when is_atom(source_label) and is_atom(dest_label) do
    relationship = to_string(relationship)
    "MATCH (s:#{to_string(source_label)} #{Cypher.cypher_properties(source_properties)}) MATCH (d:#{to_string(dest_label)} #{Cypher.cypher_properties(dest_properties)}) CREATE (s)-[r:#{relationship}]->(d) RETURN s, r, d"
    |> Cypher.run_cypher()
  end

  @doc """
  Tests if two nodes are related with a relationship type
    ## Examples
  ```
  iex> AshNeo4j.Neo4jHelper.create_node(:Actor, %{name: "Bill Nighy", born: 1949})
  iex> AshNeo4j.Neo4jHelper.create_node(:Movie, %{title: "Love Actually"})
  iex> AshNeo4j.Neo4jHelper.relate_nodes(:Actor, %{name: "Bill Nighy"}, :Movie, %{title: "Love Actually"}, :ACTED_IN)
  iex> AshNeo4j.Neo4jHelper.nodes_relate_how?(:Actor, %{name: "Bill Nighy"}, :Movie, %{title: "Love Actually"}, :ACTED_IN)
  true
  ```
  """
  def nodes_relate_how?(source_label, source_properties, dest_label, dest_properties, relationship) when is_atom(source_label) and is_atom(dest_label) and is_atom(relationship) do
    cypher = "MATCH (s:#{to_string(source_label)} #{Cypher.cypher_properties(source_properties)})-[r:#{to_string(relationship)}]->(d:#{to_string(dest_label)} #{Cypher.cypher_properties(dest_properties)}) RETURN s, r, d"
    case Cypher.run_cypher(cypher) do
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
    "MATCH (n:#{to_string(label)} #{Cypher.cypher_properties(properties)}) RETURN n"
    |> Cypher.run_cypher()
  end
end
