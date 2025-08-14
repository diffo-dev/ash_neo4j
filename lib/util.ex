defmodule AshNeo4j.Util do
  @moduledoc """
  AshNeo4j Util
  """

  @doc """
  Converts elixir snake_case to Neo4j camelCase

  ## Examples
  ```
  iex> AshNeo4j.Util.to_camel_case(:snake_case)
  :snakeCase
  iex> AshNeo4j.Util.to_camel_case(:UUID)
  :uuid
  ```
  """
  def to_camel_case(atom) when is_atom(atom) do
    splits = String.split(Atom.to_string(atom), "_")
    (String.downcase(hd(splits)) <> Enum.map_join(tl(splits), "", fn s -> String.capitalize(s) end)) |> String.to_atom()
  end
end
