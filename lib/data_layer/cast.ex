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

  def cast({:array, inner_type}, value, constraints) when is_binary(value) do
    with {:ok, decoded} <- Jason.decode(value),
         # already json decoded so call cast_ash_type rather than cast
         do: Enum.map(decoded, &cast_ash_type(inner_type, &1, constraints))
  end

  def cast(type, value, constraints) do
    case TypeClassifier.classify(type) do
      {:ok, :native, _type} ->
        value

      {:ok, :ash_base64, ash_type} ->
        cast_ash_type(ash_type, base64_decode(value), constraints)

      {:ok, :ash_json, ash_type} ->
        cast_ash_type(ash_type, json_decode(value), constraints)

      {:ok, :ash, ash_type} ->
        cast_ash_type(ash_type, value, constraints)

      _ ->
        raise "AshNeo4j.DataLayer Error casting value #{inspect(value)} of type #{inspect(type)}"
    end
  end

  defp cast_ash_type(Ash.Type.Function, value, _constraints) do
    [module_function | arity] = String.replace_leading(value, "&", "") |> String.split("/")
    module_function_splits = String.split(module_function, ".")
    function = List.last(module_function_splits)
    module = Module.concat(module_function_splits |> Enum.reverse() |> tl() |> Enum.reverse())
    Function.capture(module, String.to_atom(function), String.to_integer(hd(arity)))
  end

  defp cast_ash_type(type, value, constraints) do
    case Ash.Type.cast_stored(type, value, constraints) do
      {:ok, casted} ->
        casted

      _ ->
        raise "AshNeo4j.DataLayer Error casting value #{inspect(value)} of type #{inspect(type)}"
    end
  end

  defp base64_decode(value) do
    case Base.decode64(value) do
      {:ok, decoded} ->
        decoded

      _ ->
        raise "AshNeo4j.DataLayer Error casting value #{inspect(value)} couldn't decode Base64"
    end
  end

  defp json_decode(value) do
    case Jason.decode(value) do
      {:ok, decoded} ->
        decoded

      _ ->
        raise "AshNeo4j.DataLayer Error casting value #{inspect(value)} couldn't decode JSON"
    end
  end
end
