# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.DataLayer.Cast do
  @moduledoc "Casting for AshNeo4j.DataLayer"
  require Logger

  @doc """
  Casts an Ash.Resource.Attribute, needs to handle single values and arrays of values.
  Values may be Elixir native types, Neo4j native types, or string representations of either.
  """
  def cast(_resource, _name, nil) do
    nil
  end

  def cast(resource, name, value) when is_atom(resource) and is_atom(name) do
    attribute = Ash.Resource.Info.attribute(resource, name)

    if attribute == nil do
      Logger.warning(
        "AshNeo4j.Cast: no attribute found for resource #{inspect(resource)} and name #{inspect(name)}, returning original value"
      )

      value
    else
      cast_attribute(attribute.type, value, attribute.constraints)
    end
  end

  defp cast_attribute(_type, nil, _constraints) do
    nil
  end

  defp cast_attribute({:array, inner_type}, value, constraints) when is_list(value) do
    Enum.map(value, &cast_attribute(inner_type, &1, constraints))
  end

  defp cast_attribute(type, value, constraints) do
    ash_type = Ash.Type.get_type!(type)
    # is_resource = Ash.Resource.Info.resource?(ash_type)

    cast_ash_type(ash_type, value, constraints)
  end

  defp cast_ash_type(type, value, constraints) do
    case Ash.Type.cast_stored(type, value, constraints) do
      {:ok, casted} ->
        if is_struct(value) and !is_struct(casted) do
          # if the value was a struct we want to add a __type__ key to the map so that we can reconstruct the struct later
          Map.put(casted, :__type__, value.__struct__) |> IO.inspect(label: "casted value with __type__ added")
        else
          casted
        end

      _ ->
        Logger.warning(
          "AshNeo4j.Cast: cannot cast using Ash.Type.cast_stored for type #{inspect(type)} and value #{inspect(value)}, returning original value"
        )

        value
    end
  end
end
