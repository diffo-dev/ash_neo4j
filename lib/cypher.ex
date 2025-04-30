defmodule AshNeo4j.Cypher do
  @moduledoc """
  Ash Neo4j cypher functions
  """

  @doc """
  Converts a map to a cypher properties string.
  The map is converted to a string in the format `{key1: value1, key2: value2}`.
  This is used to create nodes in Neo4j.

  ## Examples
  ```
  iex> AshNeo4j.Cypher.cypher_properties(%{name: "Bill Nighy", born: 1949, bafta_winner: true})
  "{name: 'Bill Nighy', born: 1949, bafta_winner: true}"
  ```
  """
  def cypher_properties(map) when is_map(map) do
    properties =
      map
      |> Enum.map_join(", ",
        fn {k, v} ->
          case v do
            nil -> "#{k}: null"
            _ when is_integer(v) -> "#{k}: #{v}"
            _ when is_float(v) -> "#{k}: #{v}"
            _ when is_boolean(v) -> "#{k}: #{v}"
            _ when is_list(v) -> "#{k}: #{inspect(v)}"
            _ -> "#{k}: '#{v}'"
          end
        end)

    "{#{properties}}"
  end

  @doc """
  Runs some cypher,

  ## Examples
  ```
  iex> cypher = "CREATE (n:Actor {name: 'Bill Nighy', born: 1949, bafta_winner: true}) RETURN n"
  iex> {result, _} = run_cypher(cypher)
  iex> result
  :ok
  ```
  """
  def run_cypher(cypher) do
    Boltx.query(Bolt, cypher)
  end
end
