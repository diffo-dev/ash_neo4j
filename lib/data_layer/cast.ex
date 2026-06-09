# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.DataLayer.Cast do
  @moduledoc "Casting for AshNeo4j.DataLayer"

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

  # Nested array: each outer element is a JSON STRING (see `Dump.dump/3`). Decode
  # it, then cast the inner array back into nested native lists.
  def cast({:array, {:array, _} = inner_type}, value, constraints) when is_list(value) do
    item_constraints = TypeClassifier.item_constraints(inner_type, constraints)

    Enum.reduce_while(value, {:ok, []}, fn item, {:ok, acc} ->
      with {:ok, decoded} <- Util.json_decode(item),
           {:ok, cast_item} <- cast_nested(inner_type, decoded, item_constraints) do
        {:cont, {:ok, [cast_item | acc]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
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

      {:ok, :tensor, tensor_type} ->
        # value is the reassembled %{data:, shape:, type:} from
        # read_attribute_property; the type rebuilds the Nx tensor.
        cast_ash_type(tensor_type, value, constraints)

      {:ok, :geo, ash_type} ->
        # AshGeo geometry types: the data layer's read_attribute_property/4
        # has already decoded the stored JSON STRING into a %Geo.*{} struct
        # before we get here. cast_stored is identity for AshGeo on those
        # structs — no extra cast machinery, just follow the ash typing.
        cast_ash_type(ash_type, value, constraints)

      _ ->
        {:error, "AshNeo4j.DataLayer: cannot cast value #{inspect(value)} of type #{inspect(type)}"}
    end
  end

  # Casts a JSON-decoded nested array back into nested native lists, leaves cast
  # via the normal path. Mirror of `Dump.dump_nested/3`.
  defp cast_nested({:array, inner_type}, value, constraints) when is_list(value) do
    item_constraints = TypeClassifier.item_constraints(inner_type, constraints)

    Enum.reduce_while(value, {:ok, []}, fn item, {:ok, acc} ->
      case cast_nested(inner_type, item, item_constraints) do
        {:ok, cast_item} -> {:cont, {:ok, [cast_item | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  # Native leaves inside the JSON came back as scalars — temporal types as ISO
  # 8601 strings (see `Util.to_json_safe/1`), so re-cast through the type to
  # restore the struct; numbers/strings/booleans pass straight through.
  defp cast_nested(type, value, constraints) do
    case TypeClassifier.classify(type) do
      {:ok, :native, native} ->
        case Ash.Type.cast_stored(native, value, constraints) do
          {:ok, casted} -> {:ok, casted}
          _ -> {:ok, value}
        end

      # JSON leaf: already a decoded map (the whole element was json_decoded),
      # so cast it straight — no second json_decode.
      {:ok, :ash_json, ash_type} ->
        cast_ash_type(ash_type, value, constraints)

      _ ->
        cast(type, value, constraints)
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
          {:error, "AshNeo4j.DataLayer: cannot cast #{inspect(value)} as Function: module cannot be loaded"}
      end
    rescue
      e ->
        {:error, "AshNeo4j.DataLayer: cannot cast #{inspect(value)} as Function: #{Exception.message(e)}"}
    end
  end

  defp cast_ash_type(Ash.Type.Module, value, _constraints) do
    try do
      module = String.to_existing_atom(value)

      case Code.ensure_loaded(module) do
        {:module, _} -> {:ok, module}
        {:error, _} -> {:error, "AshNeo4j.DataLayer: cannot cast #{inspect(value)} as Module: module cannot be loaded"}
      end
    rescue
      _ -> {:error, "AshNeo4j.DataLayer: cannot cast #{inspect(value)} as Module: not a known atom"}
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
        {:error, "AshNeo4j.DataLayer: cannot cast #{inspect(value)} as #{inspect(type)}: #{Exception.message(e)}"}
    end
  end
end
