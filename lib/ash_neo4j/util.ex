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
  iex> AshNeo4j.Util.cypher_properties(%{name: "Bill Nighy", born: 1949, bafta_winner: true})
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
end
