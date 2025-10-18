# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Cypher do
  @moduledoc """
  AshNeo4j Cypher
  """

  alias AshNeo4j.BoltxHelper
  require Logger

  @doc """
  Converts a map to a cypher properties string.
  The map is converted to a string in the format `{key1: value1, key2: value2}`.

  ## Examples
  ```
  iex> AshNeo4j.Cypher.properties(%{name: "Bill Nighy", born: 1949, bafta_winner: true})
  "{name: 'Bill Nighy', born: 1949, bafta_winner: true}"
  ```
  """
  def properties(map) when is_map(map) do
    properties =
      map
      |> Enum.map_join(", ", &property(&1))

    "{#{properties}}"
  end

  defp property(property) when is_tuple(property) do
    {k, v} = property
    "#{k}: " <> value(v, "'")
  end

  defp value(v, wrap \\ nil) do
    case v do
      nil -> "null"
      _ when is_boolean(v) -> "#{v}"
      # atom must be after boolean
      _ when is_atom(v) -> wrap(":#{v}", wrap)
      _ when is_integer(v) -> "#{v}"
      _ when is_float(v) -> "#{v}"
      _ when is_list(v) -> "[" <> Enum.map_join(v, ", ", &value(&1, wrap)) <> "]"
      _ when is_function(v) -> wrap("#{inspect(v)}", wrap)
      _ when is_struct(v, Date) -> wrap(Date.to_iso8601(v), wrap)
      _ when is_struct(v, DateTime) -> wrap(DateTime.to_iso8601(v), wrap)
      _ when is_struct(v, Decimal) -> wrap("#{inspect(v)}", wrap)
      _ when is_struct(v, NaiveDateTime) -> wrap(NaiveDateTime.to_iso8601(v), wrap)
      _ when is_struct(v, Regex) -> wrap("#{inspect(v)}", wrap)
      _ when is_struct(v, Time) -> wrap(Time.to_iso8601(v), wrap)
      _ when is_struct(v, Ash.CiString) -> wrap(Ash.CiString.value(v), wrap)
      _ when is_struct(v, Duration) -> "duration(" <> wrap(Duration.to_iso8601(v), wrap) <> ")"
      _ when is_struct(v, Boltx.Types.Duration) -> wrap(BoltxHelper.to_cypher(v), wrap)
      _ when is_struct(v, MapSet) -> wrap("#{inspect(v)}", wrap)
      # following assumes embedded structs will implement to_string protocol
      _ when is_struct(v) -> wrap("#{to_string(v)}", wrap)
      # map must be after struct
      _ when is_map(v) -> wrap("#{inspect(v)}", wrap)
      _ when is_tuple(v) -> wrap("{" <> Enum.map_join(Tuple.to_list(v), ", ", &value(&1)) <> "}", wrap)
      # no specific property value format, requires String.Chars protocol
      _ -> wrap("#{v}", wrap)
    end
  end

  defp wrap(v, nil) when is_nil(nil) do
    v
  end

  defp wrap(v, wrap) when is_bitstring(wrap) do
    wrap <> v <> wrap
  end

  @doc """
  Converts a list into a remove properties string.
  The list is converted to a string in the format `n.key1, n.key2`.

  ## Examples
  ```
  iex> AshNeo4j.Cypher.remove_properties(:n, [:born, :bafta_winner])
  "n.born, n.bafta_winner"
  ```
  """
  def remove_properties(label, list) when is_atom(label) and is_list(list) do
    list
    |> Enum.map_join(", ", fn property -> "#{label}.#{property}" end)
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
  Converts a node variable, label and optional properties to cypher node.

  ## Examples
  ```
  iex> AshNeo4j.Cypher.node(:s, :Actor)
  "(s:Actor)"
  iex> AshNeo4j.Cypher.node(:s, :Actor, %{name: "Bill Nighy"})
  "(s:Actor {name: 'Bill Nighy'})"
  ```
  """
  def node(variable, label, properties \\ %{}) when is_atom(variable) and is_atom(label) and is_map(properties) do
    if properties == %{} do
      "(#{variable}:#{label})"
    else
      "(#{variable}:#{label} " <> properties(properties) <> ")"
    end
  end

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
  ```
  """
  def run(cypher) when is_bitstring(cypher) do
    Logger.debug("""
    AshNeo4.Cypher: run(#{cypher})
    """)

    boltx_result = Boltx.query(Bolt, cypher)

    if elem(boltx_result, 0) == :ok do
      Logger.debug("""
      AshNeo4j.Cypher: run result #{inspect(elem(boltx_result, 1).results)}
      """)
    end

    boltx_result
  end

  def run_expecting_deletions(cypher) when is_bitstring(cypher) do
    Logger.debug("AshNeo4.Cypher: run_expecting_deletions(#{cypher})")

    boltx_result = Boltx.query(Bolt, cypher)

    if elem(boltx_result, 0) == :ok do
      response = elem(boltx_result, 1)

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
        boltx_result
      end
    else
      boltx_result
    end
  end
end
