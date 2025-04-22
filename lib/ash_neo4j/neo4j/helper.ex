defmodule AshNeo4j.Neo4j.Helper do
  @moduledoc """
  Helpers for Neo4j
  """

  @doc """
  Delete all neo4j nodes and relationships

  ## Examples
  ```
  iex> AshNeo4j.Neo4j.Helper.delete_all()
  iex> :ok
  ```
  """
  def delete_all() do
    cypher = "MATCH (n) DETACH DELETE n"
    run_cypher(cypher)
  end

  @doc """
  Creates a neo4j node with label and properties

  ## Examples
  ```
  iex> AshNeo4j.Neo4j.Helper.create_node(:Actor, %{name: "Bill Nighy"})
  iex> :ok
  ```
  """
  def create_node(label, properties) when is_atom(label) do
    cypher = "CREATE (n:#{to_string(label)} #{AshNeo4j.Util.cypher_properties(properties)}) RETURN n"
    run_cypher(cypher)
  end

  @doc """
  Creates a neo4j node with label and properties

  ## Examples
  ```
  iex> AshNeo4j.Neo4j.Helper.merge_node(:Actor, %{name: "Bill Nighy", born: 1949})
  iex> :ok
  ```
  """
  def merge_node(label, properties) when is_atom(label) do
    cypher = "MERGE (n:#{to_string(label)} #{AshNeo4j.Util.cypher_properties(properties)}) RETURN n"
    run_cypher(cypher)
  end

  @doc """
  Relates two nodes with a relationship type
    ## Examples
  ```
  iex> result = AshNeo4j.Neo4j.Helper.relate_nodes(:Actor, %{name: "Bill Nighy", born: 1949}, :Movie, %{title: "Love Actually"}, :ACTED_IN)
  iex> :ok
  ```
  """
  def relate_nodes(source_label, source_properties, dest_label, dest_properties, relationship) when is_atom(source_label) and is_atom(dest_label) do
    relationship = to_string(relationship)
    cypher = "MERGE (s:#{to_string(source_label)} #{AshNeo4j.Util.cypher_properties(source_properties)})-[r:#{relationship}]->(d:#{to_string(dest_label)} #{AshNeo4j.Util.cypher_properties(dest_properties)}) RETURN s, r, d"
    run_cypher(cypher)
  end

  @doc """
  Tests if two nodes are related with a relationship type
    ## Examples
  ```
  iex> result = AshNeo4j.Neo4j.Helper.nodes_relate_how?(:Actor, %{name: "Bill Nighy", born: 1949}, :Movie, %{title: "Love Actually"}, :ACTED_IN)
  iex> :ok
  ```
  """
  def nodes_relate_how?(source_label, source_properties, dest_label, dest_properties, relationship) when is_atom(source_label) and is_atom(dest_label) do
    relationship = to_string(relationship)
    cypher = "MATCH (s:#{to_string(source_label)} #{AshNeo4j.Util.cypher_properties(source_properties)})-[r:#{relationship}]->(d:#{to_string(dest_label)} #{AshNeo4j.Util.cypher_properties(dest_properties)}) RETURN s, r, d"
    conn = Bolt.Sips.conn()
    case Bolt.Sips.query(conn, cypher) do
      {:ok, %Bolt.Sips.Response{records: records}} ->
        length(records) > 0
      {:error, error} ->
        IO.puts("Error running query: #{inspect(error)}")
        :error
    end
  end

  @doc """
  Reads a node from Neo4j

  ## Examples
  ```
  iex> result = AshNeo4j.Neo4j.Helper.read_node(:Actor, %{name: "Bill Nighy", born: 1949})
  iex> {:ok, %Bolt.Sips.Response{}} = result
  ```
  """
  def read_node(label, properties) when is_atom(label) do
    cypher = "MATCH (n:#{to_string(label)} #{AshNeo4j.Util.cypher_properties(properties)}) RETURN n"
    conn = Bolt.Sips.conn()
    Bolt.Sips.query(conn, cypher)
  end

  defp run_cypher(cypher) do
    conn = Bolt.Sips.conn()
    case Bolt.Sips.query(conn, cypher) do
      {:ok, %Bolt.Sips.Response{}} ->
        :ok

      {:error, error} ->
        IO.puts("Error running query: #{inspect(error)}")
        :error
    end
  end
end
