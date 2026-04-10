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

  defp ash_type_json?(type) do
    type in [
      Ash.Type.Map,
      Ash.Type.Struct,
      Ash.Type.Union
    ] or ash_type_other_map?(type)
  end

  def neo4j_native?(type) do
    type in [
      Ash.Type.Boolean,
      Ash.Type.Date,
      Ash.Type.Duration,
      Ash.Type.Float,
      Ash.Type.Integer,
      Ash.Type.NaiveDatetime,
      Ash.Type.String,
      Ash.Type.Time,
      Ash.Type.TimeUsec,
      Ash.Type.UUID,
      Ash.Type.UUIDv7
    ]
  end

  defp unsupported?(type) do
    type in [
      Ash.Type.Binary,
      Ash.Type.File,
      Ash.Type.Keyword,
      Ash.Type.Term,
      Ash.Type.Tuple,
      Ash.Type.UrlEncodedBinary,
      Ash.Type.Vector
    ]
  end
end
