# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.DataLayer.Dump do
  @moduledoc "Dumping for AshNeo4j.DataLayer"

  alias AshNeo4j.DataLayer.TypeClassifier
  alias AshNeo4j.Util

  @doc """
  Dumps an Ash.Resource.Attribute, needs to handle single values and arrays of values.
  Values may be Elixir native types, Neo4j native types, or string representations of either.
  """
  def dump(type, value, constraints \\ [])

  def dump(_type, nil, _constraints) do
    nil
  end

  # Nested array. Neo4j has no collection-of-collections, so the outer axis
  # stays a native LIST and each inner array is encoded as a JSON STRING (any
  # deeper nesting lives inside that JSON). Symmetric with `Cast.cast/3`.
  def dump({:array, {:array, _} = inner_type}, value, constraints) when is_list(value) do
    item_constraints = TypeClassifier.item_constraints(inner_type, constraints)
    Enum.map(value, fn inner -> inner_type |> dump_nested(inner, item_constraints) |> json_encode() end)
  end

  def dump({:array, inner_type}, value, constraints) when is_list(value) do
    item_constraints = TypeClassifier.item_constraints(inner_type, constraints)
    Enum.map(value, &dump(inner_type, &1, item_constraints))
  end

  def dump(type, value, constraints) do
    case TypeClassifier.classify(type) do
      {:ok, :native, _type} ->
        # pass through, since Neo4j Bolt driver will handle conversion of native types
        value

      {:ok, :ash_base64, ash_type} ->
        # ash values that are dumped and base64 encoded
        dump_ash_type(ash_type, value, constraints)
        |> base64_encode()

      {:ok, :ash_json, ash_type} ->
        # ash values that are dumped and jason encoded
        dump_ash_type(ash_type, value, constraints)
        |> json_encode()

      {:ok, :ash_uuid, _ash_type} ->
        value

      {:ok, :ash, ash_type} ->
        # other ash types are just dumped for Neo4j to handle
        dump_ash_type(ash_type, value, constraints)

      {:ok, :geo, ash_type} ->
        # AshGeo geometry types: dump_to_native is identity on %Geo.*{}.
        # The data layer's dump_properties detects the Geo struct returned
        # here and routes through promote_geo/3 — encoding RFC 7946 JSON
        # canonical at <attr>.json + indexable companions alongside.
        dump_ash_type(ash_type, value, constraints)

      {:error, reason, _} ->
        raise "AshNeo4j.DataLayer Error dumping value #{inspect(value)} of type #{inspect(type)}, #{reason}"

      _ ->
        raise "AshNeo4j.DataLayer Error dumping value #{inspect(value)} of type #{inspect(type)}"
    end
  end

  # Dumps a nested array into nested *native* Elixir lists (leaves dumped via the
  # normal path), so the whole inner structure is JSON-encoded once at the outer
  # boundary in `dump/3` rather than per level.
  defp dump_nested({:array, inner_type}, value, constraints) when is_list(value) do
    item_constraints = TypeClassifier.item_constraints(inner_type, constraints)
    Enum.map(value, &dump_nested(inner_type, &1, item_constraints))
  end

  defp dump_nested(type, value, constraints) do
    case TypeClassifier.classify(type) do
      # JSON leaves: keep the dumped value json-*safe* (a map), not yet a string,
      # so the single json_encode at the outer boundary yields clean nested JSON
      # instead of double-escaped strings.
      {:ok, :ash_json, ash_type} -> dump_ash_type(ash_type, value, constraints)
      _ -> dump(type, value, constraints)
    end
  end

  defp dump_ash_type(Ash.Type.Decimal, value, constraints) do
    {:ok, dumped_value} = Ash.Type.dump_to_native(Ash.Type.Decimal, value, constraints)
    Decimal.to_string(dumped_value)
  end

  defp dump_ash_type(Ash.Type.Function, value, _constraints) do
    info = Function.info(value)

    case info[:type] do
      :external ->
        "&" <>
          Atom.to_string(info[:module]) <> "." <> Atom.to_string(info[:name]) <> "/" <> Integer.to_string(info[:arity])

      _ ->
        raise "AshNeo4j.DataLayer Error dumping value #{inspect(value)} of type Function: function is not external"
    end
  end

  defp dump_ash_type(type, value, constraints) do
    case Ash.Type.dump_to_native(type, value, constraints) do
      {:ok, native} ->
        native

      _ ->
        raise "AshNeo4j.DataLayer Error dumping value #{inspect(value)} of type #{inspect(type)} to native"
    end
  end

  defp base64_encode(value), do: Base.encode64(value)

  defp json_encode(value) do
    case Util.json_encode(value) do
      {:ok, encoded} ->
        encoded

      _ ->
        raise "AshNeo4j.DataLayer Error dumping value #{inspect(value)} couldn't encode JSON"
    end
  end
end
