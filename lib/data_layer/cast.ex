# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.DataLayer.Cast do
  @moduledoc "Casting for AshNeo4j.DataLayer"
  require Logger

  alias AshNeo4j.DataLayer.TypeClassifier
  alias AshNeo4j.Util

  @doc """
  Casts an Ash.Resource.Attribute, handles single values and arrays of values.
  Values may be Elixir native types, Neo4j native types.
  Returns {:ok, value} | {:error, reason}
  """
  def cast(type, value, constraints \\ [])

  def cast(_type, nil, _constraints) do
    {:ok, nil}
  end

  def cast({:array, inner_type}, value, constraints) when is_list(value) do
    item_constraints = TypeClassifier.item_constraints(inner_type, constraints)

    Enum.reduce_while(value, {:ok, []}, fn item, {:ok, acc} ->
      case cast(inner_type, item, item_constraints) do
        {:ok, cast_item} -> {:cont, {:ok, [cast_item | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  def cast(type, value, constraints) do
    case TypeClassifier.classify(type) do
      {:ok, :native, _type} ->
        {:ok, value}

      {:ok, :ash_base64, ash_type} ->
        case Util.base64_decode(value) do
          {:ok, decoded} -> cast_ash_type(ash_type, decoded, constraints)
          {:error, reason} -> {:error, reason}
        end

      {:ok, :ash_json, ash_type} ->
        case Util.json_decode(value) do
          {:ok, decoded} -> cast_ash_type(ash_type, decoded, constraints)
          {:error, reason} -> {:error, reason}
        end

      {:ok, :ash_uuid, _ash_type} ->
        {:ok, value}

      {:ok, :ash, ash_type} ->
        cast_ash_type(ash_type, value, constraints)

      _ ->
        {:error, "AshNeo4j.DataLayer: cannot cast value #{inspect(value)} of type #{inspect(type)}"}
    end
  end

  defp cast_ash_type(Ash.Type.Function, value, _constraints) do
    try do
      [module_function | arity] = String.replace_leading(value, "&", "") |> String.split("/")
      module_function_splits = String.split(module_function, ".")
      function = List.last(module_function_splits)
      module = Module.concat(module_function_splits |> Enum.reverse() |> tl() |> Enum.reverse())

      case Code.ensure_loaded(module) do
        {:module, _} ->
          {:ok, Function.capture(module, String.to_atom(function), String.to_integer(hd(arity)))}

        {:error, _} ->
          {:error, "AshNeo4j.DataLayer: function module #{inspect(module)} is not loaded"}
      end
    rescue
      e ->
        {:error, "AshNeo4j.DataLayer: cannot cast function #{inspect(value)}: #{Exception.message(e)}"}
    end
  end

  defp cast_ash_type(Ash.Type.Module, value, _constraints) do
    try do
      module = String.to_existing_atom(value)

      case Code.ensure_loaded(module) do
        {:module, _} -> {:ok, module}
        {:error, _} -> {:error, "AshNeo4j.DataLayer: module #{inspect(value)} is not loaded"}
      end
    rescue
      _ -> {:error, "AshNeo4j.DataLayer: module #{inspect(value)} is not a known atom"}
    end
  end

  defp cast_ash_type(type, value, constraints) do
    try do
      case Ash.Type.cast_stored(type, value, constraints) do
        {:ok, casted} ->
          {:ok, casted}

        {:error, reason} ->
          {:error, "AshNeo4j.DataLayer: cannot cast #{inspect(value)} as #{inspect(type)}: #{inspect(reason)}"}

        :error ->
          {:error, "AshNeo4j.DataLayer: cannot cast #{inspect(value)} as #{inspect(type)}"}
      end
    rescue
      e ->
        {:error, "AshNeo4j.DataLayer: exception casting #{inspect(value)} as #{inspect(type)}: #{Exception.message(e)}"}
    end
  end
end
