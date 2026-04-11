# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Cypher do
  @moduledoc """
  AshNeo4j Cypher
  Functions for converting Elixir data structures to Cypher query components and running Cypher queries against a Neo4j database.
  Ideally has no specific knowledge of Ash

  """

  require Logger

  @spec remove_properties(atom(), maybe_improper_list()) :: binary()
  @doc """
  Converts a list of property names into a remove properties string.
  The list is converted to a string in the format `n.key1, n.key2`.

  ## Examples
  ```
  iex> AshNeo4j.Cypher.remove_properties(:n, [:born, :bafta_winner])
  "n.born, n.bafta_winner"
  ```
  """
  def remove_properties(label, names) when is_atom(label) and is_list(names) do
    names
    |> Enum.map_join(", ", fn name -> "#{label}.#{name}" end)
  end

  @doc """
  Converts a node variable, label and optional properties to cypher expression

  ## Examples
  ```
  iex> AshNeo4j.Cypher.expression(:s, "name", "in", "[Bill Nighy]")
  "s.name in [Bill Nighy]"
  iex> AshNeo4j.Cypher.expression(:s, "name", "in", "[]")
  "s.name IS NULL"
  iex> AshNeo4j.Cypher.expression(:s, "name", "is_nil", true)
  "s.name IS NULL"
  iex> AshNeo4j.Cypher.expression(:s, "name", "is_nil", false)
  "s.name IS NOT NULL"
  iex> AshNeo4j.Cypher.expression(:s, "name", "contains", "access")
  "s.name CONTAINS 'access'"
  ```
  """
  def expression(variable, left, operator, right)
      when is_atom(variable) and is_bitstring(left) and is_bitstring(operator) do
    cond do
      operator == "in" && right == "[]" ->
        "#{variable}.#{left} IS NULL"

      operator == "is_nil" && right ->
        "#{variable}.#{left} IS NULL"

      operator == "is_nil" && !right ->
        "#{variable}.#{left} IS NOT NULL"

      operator == "contains" ->
        "#{variable}.#{left} CONTAINS '#{right}'"

      true ->
        "#{variable}.#{left} #{operator} #{right}"
    end
  end

  @doc """
  Converts a node variable and labels to basic cypher node expression.

  ## Examples
  ```
  iex> AshNeo4j.Cypher.node(:s, [:Actor])
  "(s:Actor)"
  ```
  """
  def node(variable, labels) when is_atom(variable) and is_list(labels) do
    "(#{variable}:#{Enum.join(labels, ":")})"
  end

  @doc """
  Converts a node variable, labels and optional property map to cypher properties string and variable prefixed parameters map.

  ## Examples
  ```
  iex> AshNeo4j.Cypher.parameterized_node(:s, [:Actor])
  {"(s:Actor)", %{}}
  iex> AshNeo4j.Cypher.parameterized_node(:s, [:Cinema, :Actor], %{name: "Bill Nighy"})
  {"(s:Cinema:Actor {name: $s_name})", %{"s_name" =>"Bill Nighy"}}
  ```
   Note: the properties map is converted to parameter names by prefixing the keys with `$<variable>`, and the original values are returned in a separate map for use as query parameters.
  """
  def parameterized_node(variable, labels, properties \\ %{})
      when is_atom(variable) and is_list(labels) and is_map(properties) do
    if properties == %{} do
      {node(variable, labels), %{}}
    else
      {property_cypher, parameters} = parameterized_properties(variable, properties)
      label_string = Enum.join(labels, ":")
      {"(#{variable}:#{label_string} #{property_cypher})", parameters}
    end
  end

  @doc """
  Converts a node variable and optional property map to cypher properties string and variable prefixed parameters map.

  ## Examples
  ```
  iex> AshNeo4j.Cypher.parameterized_properties(:s)
  {"{}", %{}}
  iex> AshNeo4j.Cypher.parameterized_properties(:s, %{name: "Bill Nighy"})
  {"{name: $s_name}", %{"s_name" =>"Bill Nighy"}}
  ```
  """
  def parameterized_properties(variable, properties \\ %{}) when is_atom(variable) and is_map(properties) do
    parameterized_properties =
      properties
      |> Enum.map_join(", ", fn {k, _v} -> "#{k}: $#{variable}_#{k}" end)

    parameters = Map.new(properties, fn {k, v} -> {"#{variable}_#{k}", v} end)

    {"{#{parameterized_properties}}", parameters}
  end

  @spec relationship(atom(), atom()) :: <<_::32, _::_*8>>
  @doc """
  Converts a relationship variable, label and optional direction to cypher relationship.

  ## Examples
  ```
  iex> AshNeo4j.Cypher.relationship(:r, :ACTED_IN, :outgoing)
  "-[r:ACTED_IN]->"
  iex> AshNeo4j.Cypher.relationship(:r, :ACTED_IN, :incoming)
  "<-[r:ACTED_IN]-"
  iex> AshNeo4j.Cypher.relationship(:r, :KNOWS)
  "-[r:KNOWS]-"
  ```
  """
  def relationship(variable, label, direction \\ nil)
      when is_atom(variable) and is_atom(label) and is_atom(direction) do
    if variable == nil do
      case direction do
        :outgoing ->
          "-[#{label}]->"

        :incoming ->
          "<-[#{label}]-"

        _ ->
          "-[#{label}]-"
      end
    else
      case direction do
        :outgoing ->
          "-[#{variable}:#{label}]->"

        :incoming ->
          "<-[#{variable}:#{label}]-"

        _ ->
          "-[#{variable}:#{label}]-"
      end
    end
  end

  @doc """
  Converts a node_relationship tuple to cypher clause, ignoring the label

  ## Examples
  ```
  iex> AshNeo4j.Cypher.relationship({:movies, :ACTED_IN, :outgoing})
  "-[r:ACTED_IN]->"
  iex> AshNeo4j.Cypher.relationship(nil)
  "-[r]-"
  ```
  """
  def relationship(node_relationship) when is_tuple(node_relationship) do
    relationship(:r, elem(node_relationship, 1), elem(node_relationship, 2))
  end

  def relationship(nil) when is_nil(nil), do: "-[r]-"

  @doc """
  Runs some cypher

  ## Examples
  ```
  iex> cypher = "CREATE (n:Actor {name: 'Bill Nighy', born: 1949, bafta_winner: true}) RETURN n"
  iex> {result, _} = AshNeo4j.Cypher.run(cypher)
  iex> result
  :ok
  iex> cypher = "MATCH (n:Actor {name: $name}) RETURN n"
  iex> params = %{name: "Bill Nighy"}
  iex> {result, _} = AshNeo4j.Cypher.run(cypher, params)
  iex> result
  :ok
  ```
  """
  def run(cypher, params \\ %{}) when is_bitstring(cypher) do
    Logger.debug("""
    AshNeo4j.Cypher: run(#{cypher}, #{inspect(params)})
    """)

    bolty_result = Bolty.query(Bolt, cypher, params)

    if elem(bolty_result, 0) == :ok do
      Logger.debug("""
      AshNeo4j.Cypher: run result #{inspect(elem(bolty_result, 1).results)}
      """)
    end

    bolty_result
  end

  def run_expecting_deletions(cypher, params \\ %{}) when is_bitstring(cypher) do
    Logger.debug("AshNeo4.Cypher: run_expecting_deletions(#{cypher})")

    bolty_result = Bolty.query(Bolt, cypher, params)

    if elem(bolty_result, 0) == :ok do
      response = elem(bolty_result, 1)

      deleted_nodes =
        case response.stats do
          [] ->
            0

          %{} ->
            Map.get(response.stats, "nodes-deleted", 0)
        end

      if deleted_nodes == 0 do
        Logger.error("AshNeo4j.Cypher: nothing deleted")
        {:error, "nothing deleted"}
      else
        Logger.debug("AshNeo4j.Cypher: run_expecting_deletions deleted #{deleted_nodes} nodes")
        bolty_result
      end
    else
      bolty_result
    end
  end
end
