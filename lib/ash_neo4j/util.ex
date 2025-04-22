defmodule AshNeo4j.Util do
  @moduledoc """
  Ash Neo4j utility functions
  """

  @doc """
  Converts a map to a cypher properties string.
  The map is converted to a string in the format `{key1: value1, key2: value2}`.
  This is used to create nodes in Neo4j.

  ## Examples
  ```
  iex> AshNeo4j.Util.cypher_properties(%{name: "Bill Nighy", born: 1949})
  iex> "{name: 'Bill Nighy', born: 1949}"
  ```
  """
  def cypher_properties(map) when is_map(map) do
    properties =
      map
      |> Enum.map_join(", ", fn {k, v} -> "#{k}: '#{v}'" end)

    "{#{properties}}"
  end
end
