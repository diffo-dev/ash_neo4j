# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.DataLayer.Cast do
  @moduledoc "Casting for AshNeo4j.DataLayer"
  require Logger

  alias AshNeo4j.DataLayer.TypeClassifier

  @doc """
  Casts an Ash.Resource.Attribute, handles single values and arrays of values.
  Values may be Elixir native types, Neo4j native types
  """
  def cast(type, value, constraints \\ [])

  def cast(_type, nil, _constraints) do
    nil
  end

  def cast({:array, inner_type}, value, constraints) when is_list(value) do
    Enum.map(value, &cast(inner_type, &1, constraints))
  end

  def cast(type, value, constraints) do
    case TypeClassifier.classify(type) do
      {:ok, :native, _type} ->
        value

      {:ok, :ash_json, ash_type} ->
        with {:ok, decoded} <- Jason.decode(value), do: cast_ash_type(ash_type, decoded, constraints)

      {:ok, :ash, ash_type} ->
        cast_ash_type(ash_type, value, constraints)
    end
  end

  defp cast_ash_type(Ash.Type.Function, value, _constraints) when is_bitstring(value) do
    [module_function | arity] = String.replace_leading(value, "&", "") |> String.split("/")
    module_function_splits = String.split(module_function, ".")
    function = List.last(module_function_splits)
    module = Module.concat(module_function_splits |> Enum.reverse() |> tl() |> Enum.reverse())
    Function.capture(module, String.to_atom(function), String.to_integer(hd(arity)))
  end

  defp cast_ash_type(Ash.Type.Keyword, value, constraints) when is_bitstring(value) do
    with {:ok, decoded_value} <- Jason.decode!(value) do
      Ash.Type.cast_stored(Ash.Type.Keyword, decoded_value, constraints)
    end
  end

  defp cast_ash_type(type, value, constraints) do
    case Ash.Type.cast_stored(type, value, constraints) do
      {:ok, casted} ->
        casted

      _ ->
        Logger.warning(
          "AshNeo4j.DataLayer.Cast: cannot cast using Ash.Type.cast_stored for type #{inspect(type)} and value #{inspect(value)}, returning original value"
        )

        value
    end
  end
end
