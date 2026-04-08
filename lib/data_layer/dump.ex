# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.DataLayer.Dump do
  @moduledoc "Dumping for AshNeo4j.DataLayer"

  alias AshNeo4j.DataLayer.TypeClassifier

  @doc """
  Dumps an Ash.Resource.Attribute, needs to handle single values and arrays of values.
  Values may be Elixir native types, Neo4j native types, or string representations of either.
  """
  def dump(type, value, constraints \\ [])

  def dump(type, value, constraints) do
    case TypeClassifier.classify(type) do
      {:ok, :native, _type} ->
        # pass through, since Neo4j Bolt driver will handle conversion of native types
        value

      {:ok, :ash_json, ash_type} ->
        # ash values that are dumped and jason encoded
        dump_ash_type(ash_type, value, constraints)
        |> Jason.encode!()

      {:ok, :ash, ash_type} ->
        # other ash types are just dumped for Neo4j to handle
        dump_ash_type(ash_type, value, constraints)

      {:ok, :array, {:ok, :native, _inner_type}} ->
        # pass through, since Neo4j Bolt driver will handle conversion of native array types
        value

      {:ok, :array, {:ok, :ash_type, inner_type}} ->
        # ash type arrays must be dumped to native arrays before encoding, since the encoding may differ based on the inner type
        Enum.into(value, [], &dump_ash_type(inner_type, &1, constraints))
        |> Jason.encode!()

      {:ok, :array, {:ok, _classification, _inner_type}} ->
        # non-native arrays are json encoded
        value
        |> Jason.encode!(value)

      {:ok, :array, {:error, reason, _}} ->
        raise "AshNeo4j.DataLayer.Dump Error dumping value #{inspect(value)} of array type #{inspect(type)}, #{reason}"

      {:error, reason, _} ->
        raise "AshNeo4j.DataLayer.Dump Error dumping value #{inspect(value)} of type #{inspect(type)}, #{reason}"

      _ ->
        raise "AshNeo4j.DataLayer.Dump Error dumping value #{inspect(value)} of type #{inspect(type)}"
    end
  end

  defp dump_ash_type(Ash.Type.DateTime, value, constraints) do
    {:ok, dumped_value} = Ash.Type.dump_to_native(Ash.Type.DateTime, value, constraints)
    DateTime.to_iso8601(dumped_value)
  end

  defp dump_ash_type(Ash.Type.Function, value, _constraints) do
    info = Function.info(value)
    "&" <> Atom.to_string(info[:module]) <> "." <> Atom.to_string(info[:name]) <> "/" <> Integer.to_string(info[:arity])
  end

  defp dump_ash_type(Ash.Type.UtcDatetime, value, constraints) do
    {:ok, dumped_value} = Ash.Type.dump_to_native(Ash.Type.UtcDatetime, value, constraints)
    DateTime.to_iso8601(dumped_value)
  end

  defp dump_ash_type(Ash.Type.UtcDatetimeUsec, value, constraints) do
    {:ok, dumped_value} = Ash.Type.dump_to_native(Ash.Type.DateTime, value, constraints)
    DateTime.to_iso8601(dumped_value)
  end

  defp dump_ash_type(type, value, constraints) do
    case Ash.Type.dump_to_native(type, value, constraints) do
      {:ok, native} ->
        native

      _ ->
        raise "AshNeo4j.DataLayer.Dump Error dumping value #{inspect(value)} of type #{inspect(type)} to native"
    end
  end
end
