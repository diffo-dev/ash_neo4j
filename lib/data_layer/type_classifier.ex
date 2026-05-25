# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.DataLayer.TypeClassifier do
  @moduledoc "Type Classifier for AshNeo4j.DataLayer"
  require Logger

  @doc """
  Classifies the type to assist Cast and Dump
  """
  def classify(type \\ nil)

  def classify(nil), do: {:error, :unrecognized, nil}

  def classify(type) do
    try do
      type = Ash.Type.get_type!(type)

      cond do
        array?(type) ->
          {:ok, :array, classify(elem(type, 1))}

        neo4j_native?(type) ->
          {:ok, :native, type}

        unsupported?(type) ->
          {:error, :unsupported, type}

        ash_type_base64?(type) ->
          {:ok, :ash_base64, type}

        ash_type_uuid?(type) ->
          {:ok, :ash_uuid, type}

        ash_type_json?(type) ->
          {:ok, :ash_json, type}

        Ash.Type.ash_type?(type) ->
          {:ok, :ash, type}

        true ->
          {:error, :unrecognized, type}
      end
    rescue
      RuntimeError ->
        {:error, :unrecognized, type}
    end
  end

  @doc """
  Lists invalid types, checked recursively
  """

  def invalid_types(type, constraints, path \\ [])

  def invalid_types({:array, inner_type}, constraints, path) do
    item_constraints = item_constraints(inner_type, constraints)
    invalid_types(inner_type, item_constraints, path)
  end

  def invalid_types(type, constraints, path) do
    case classify(type) do
      {:error, reason, _} ->
        [{[], reason, type}]

      {:ok, :ash_json, _} ->
        cond do
          Ash.Type.NewType.new_type?(type) ->
            type.subtype_constraints()
            |> Keyword.get(:fields, Keyword.get(type.subtype_constraints(), :types, []))
            |> flat_map_field_errors(path)

          Ash.Type.embedded_type?(type) ->
            Ash.Resource.Info.attributes(type)
            |> Enum.flat_map(fn attr ->
              invalid_types(attr.type, attr.constraints, path ++ [attr.name])
            end)

          true ->
            constraints
            |> Keyword.get(:fields, Keyword.get(constraints, :types, []))
            |> flat_map_field_errors(path)
        end

      _ ->
        []
    end
  end

  defp flat_map_field_errors(fields, path) do
    Enum.flat_map(fields, fn {name, field_config} ->
      field_type = Ash.Type.get_type(field_config[:type])
      field_constraints = field_config[:constraints] || []
      invalid_types(field_type, field_constraints, path ++ [name])
    end)
  end

  defp array?(type) do
    case type do
      {:array, _} -> true
      _ -> false
    end
  end

  defp ash_type_other_map?(type) do
    Ash.Type.ash_type?(type) and !Ash.Type.builtin?(type) and
      Ash.Type.storage_type(type) == :map
  end

  defp ash_type_uuid?(type) do
    Ash.Type.ash_type?(type) and
      Ash.Type.storage_type(type) == :uuid
  end

  defp ash_type_base64?(type) do
    Ash.Type.ash_type?(type) and
      Ash.Type.storage_type(type) == :binary and
      type != Ash.Type.Function
  end

  defp ash_type_json?(type) do
    type in [
      Ash.Type.Keyword,
      Ash.Type.Map,
      Ash.Type.Struct,
      Ash.Type.Tuple,
      Ash.Type.Union
    ] or ash_type_other_map?(type)
  end

  def neo4j_native?(type) do
    type in [
      AshNeo4j.Type.Point,
      Ash.Type.Boolean,
      Ash.Type.Date,
      Ash.Type.Duration,
      Ash.Type.Float,
      Ash.Type.Integer,
      Ash.Type.NaiveDatetime,
      Ash.Type.String,
      Ash.Type.Time,
      Ash.Type.TimeUsec
    ]
  end

  defp unsupported?(type) do
    type in [
      Ash.Type.File,
      Ash.Type.Term,
      Ash.Type.Vector
    ]
  end

  @doc """
  Merges item constraints for array types.
  """
  def item_constraints(inner_type, constraints) when is_atom(inner_type) and is_list(constraints) do
    explicit_items = constraints[:items] || []

    subtype =
      (Ash.Type.NewType.new_type?(inner_type) && inner_type.subtype_constraints()) || []

    Keyword.merge(subtype, explicit_items)
  end
end
