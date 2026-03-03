# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.DataLayer.Cast do
  @moduledoc "Casting for AshNeo4j.DataLayer"
  require Logger

  @struct_name_regex Regex.compile!("%(.*?){")
  @struct_properties_regex Regex.compile!("{(.*?)}$")

  @doc """
  Casts an Ash.Resource.Attribute
  """
  def cast(resource, name, value) do
    attribute = Ash.Resource.Info.attribute(resource, name)

    if value == nil do
      nil
    else
      if attribute == nil do
        Logger.warning(
          "AshNeo4j.Cast: cannot cast as name #{name} is not an attribute of resource #{inspect(resource)}"
        )

        value
      else
        case attribute.type do
          Ash.Type.Atom ->
            cast_atom(value)

          Ash.Type.String ->
            cast_string(value)

          Ash.Type.UUID ->
            cast_string(value)

          Ash.Type.Boolean ->
            value

          Ash.Type.Integer ->
            value

          Ash.Type.Float ->
            value

          Ash.Type.Binary ->
            value

          Ash.Type.CiString ->
            value

          Ash.Type.Function ->
            cast_function(value)

          Ash.Type.Module ->
            cast_atom(value)

          Ash.Type.Date ->
            Date.from_iso8601!(value)

          Ash.Type.DateTime ->
            cast_datetime(value)

          Ash.Type.UtcDatetime ->
            cast_datetime(value)

          Ash.Type.Duration ->
            cast_duration(value)

          Ash.Type.UtcDatetimeUsec ->
            cast_datetime(value)

          Ash.Type.NaiveDatetime ->
            NaiveDateTime.from_iso8601!(value)

          Ash.Type.Time ->
            Time.from_iso8601!(value)

          Ash.Type.TimeUsec ->
            Time.from_iso8601!(value)

          Ash.Type.Map ->
            cast_map(value)

          Ash.Type.Struct ->
            cast_struct(value)

          Ash.Type.Keyword ->
            cast_list(value)

          Ash.Type.Tuple ->
            cast_tuple(value)

          Ash.Type.Decimal ->
            cast_decimal(value)

          Ash.Type.Term ->
            cast(value)

          Ash.Type.Union ->
            cast(value)

          Ash.Type.UrlEncodedBinary ->
            cast_string(value)

          {:array, _} ->
            cast_list(value)

          _name ->
            cast(value)
        end
      end
    end
  end

  defp cast_atom(nil) when is_nil(nil) do
    nil
  end

  defp cast_atom(value) when is_binary(value) do
    String.to_atom(String.replace_leading(value, ":", ""))
  end

  defp cast_function(value) when is_binary(value) do
    [module_function | arity] = String.replace_leading(value, "&", "") |> String.split("/")
    module_function_splits = String.split(module_function, ".")
    function = List.last(module_function_splits)
    module = Module.concat(module_function_splits |> Enum.reverse() |> tl() |> Enum.reverse())
    Function.capture(module, String.to_atom(function), String.to_integer(hd(arity)))
  end

  defp cast_struct(nil) when is_nil(nil) do
    nil
  end

  defp cast_struct(value) when is_binary(value) do
    cond do
      String.starts_with?(value, "Decimal.new(\"") && String.ends_with?(value, "\")") ->
        cast_decimal(value)

      String.starts_with?(value, "MapSet.new(") && String.ends_with?(value, ")") ->
        cast_mapset(value)

      String.starts_with?(value, "~r/") ->
        cast_regex(value)

      true ->
        case struct_name(value) do
          nil ->
            value

          name ->
            module = Module.concat([name])
            properties = cast_struct_properties(value)

            struct(module, properties)
            |> Map.replace(:__meta__, %Ecto.Schema.Metadata{
              state: :loaded
            })
        end
    end
  end

  defp struct_name(value) when is_binary(value) do
    Regex.run(@struct_name_regex, value) |> Enum.at(1)
  end

  defp cast_struct_properties(value) when is_binary(value) do
    Regex.run(@struct_properties_regex, value)
    |> Enum.at(1)
    |> split_properties()
    |> Enum.into([], &cast_property(&1))
  end

  defp cast_property(property) when is_binary(property) do
    trimmed = String.trim(property)

    cond do
      String.contains?(trimmed, "=>") ->
        # "\"aEnd\"" => 1
        unquoted = String.replace(trimmed, "\"", "")
        splits = String.split(unquoted, "=>")
        key = String.trim(hd(splits))
        value = String.trim(hd(tl(splits)))
        {cast(key), cast(value)}

      true ->
        splits = String.split(trimmed, ":")
        key = hd(splits)
        value = Enum.map_join(tl(splits), ":", &String.trim(&1))
        {String.to_atom(key), cast(value)}
    end
  end

  ## TODO is this working since wouldn't we expect an Ash.Type.DateTime?
  defp cast_datetime(value) when is_bitstring(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, 0} ->
        datetime

      {:error, _message} ->
        Logger.warning("AshNeo4j.Cast: value #{value} can't be parsed as DateTime")
        value
    end
  end

  defp cast_duration(value) do
    case Ash.Type.Duration.cast_input(value, []) do
      {:ok, duration} ->
        duration

      {:error, _message} ->
        Logger.warning("AshNeo4j.Cast: value #{value} can't be parsed as Duration")
        value
    end
  end

  defp cast(atom) when is_atom(atom) do
    atom
  end

  defp cast(boolean) when is_boolean(boolean) do
    boolean
  end

  defp cast(integer) when is_integer(integer) do
    integer
  end

  defp cast(float) when is_float(float) do
    float
  end

  defp cast(value) when is_binary(value) do
    case value do
      "nil" ->
        nil

      "true" ->
        true

      "false" ->
        false

      _ ->
        cond do
          String.starts_with?(value, ":") ->
            cast_atom(value)

          String.starts_with?(value, "\"") && String.ends_with?(value, "\"") ->
            cast_string(value)

          String.starts_with?(value, "[") && String.ends_with?(value, "]") ->
            cast_list(value)

          String.starts_with?(value, "%{") && String.ends_with?(value, "}") ->
            cast_map(value)

          String.starts_with?(value, "%") && String.contains?(value, "{") && String.ends_with?(value, "}") ->
            cast_struct(value)

          String.starts_with?(value, "{") && String.ends_with?(value, "}") ->
            cast_tuple(value)

          String.starts_with?(value, "MapSet.new(") && String.ends_with?(value, ")") ->
            cast_mapset(value)

          String.starts_with?(value, "Decimal.new(\"") && String.ends_with?(value, "\")") ->
            cast_decimal(value)

          String.starts_with?(value, "~r/") ->
            cast_regex(value)

          true ->
            case Integer.parse(value) do
              {integer, ""} ->
                integer

              {_integer, _} ->
                case Float.parse(value) do
                  {float, _} ->
                    float

                  :error ->
                    Logger.warning("AshNeo4j.Cast: value #{value} has leading integer but isn't an integer or float")
                    value
                end

              :error ->
                Logger.warning("AshNeo4j.Cast: no cast for value #{value}")
                value
            end
        end
    end
  end

  defp cast(list) when is_list(list) do
    cast_list(list)
  end

  defp cast(map) when is_map(map) do
    cast_map(map)
  end

  defp cast_string(nil) when is_nil(nil) do
    nil
  end

  defp cast_string(value) when is_bitstring(value) do
    value
    |> String.replace_leading("\"", "")
    |> String.replace_trailing("\"", "")
  end

  defp cast_list(nil) when is_nil(nil) do
    nil
  end

  defp cast_list(value) when is_list(value) do
    value
    |> Enum.into([], &cast(&1))
  end

  defp cast_list(value) when is_bitstring(value) do
    value
    |> String.replace_leading("[", "")
    |> String.replace_trailing("]", "")
    |> String.split(",")
    |> Enum.into([], &cast(String.trim(&1)))
  end

  defp cast_map(nil) when is_nil(nil) do
    nil
  end

  defp cast_map(value) when is_map(value) do
    value
    |> Enum.into(%{}, &cast(&1))
  end

  defp cast_map(value) when is_bitstring(value) do
    value
    |> String.replace_leading("%{", "")
    |> String.replace_trailing("}", "")
    |> String.split(",")
    |> Enum.into(%{}, &cast_property(&1))
  end

  defp cast_tuple(nil) when is_nil(nil) do
    nil
  end

  defp cast_tuple(value) when is_tuple(value) do
    value
  end

  defp cast_tuple(value) when is_bitstring(value) do
    value
    |> String.replace_leading("{", "")
    |> String.replace_trailing("}", "")
    |> String.split(",")
    |> Enum.into([], &cast(String.trim(&1)))
    |> List.to_tuple()
  end

  defp cast_decimal(nil) when is_nil(nil) do
    nil
  end

  defp cast_decimal(value) when is_bitstring(value) do
    string =
      value
      |> String.replace_leading("Decimal.new(\"", "")
      |> String.replace_trailing("\")", "")

    case Decimal.parse(string) do
      {decimal, _} ->
        decimal

      :error ->
        Logger.warning("AshNeo4j.Cast: value #{value} can't be parsed as a Decimal")
        value
    end
  end

  defp cast_mapset(value) when is_bitstring(value) do
    value
    |> String.replace_leading("MapSet.new(", "")
    |> String.replace_trailing(")", "")
    |> cast_list()
    |> MapSet.new()
  end

  defp cast_regex(value) when is_bitstring(value) do
    splits = String.split(value, "/")

    case length(splits) do
      2 ->
        case Regex.compile(Enum.at(splits, 1)) do
          {:ok, regex} ->
            regex

          {:error, _} ->
            Logger.warning("AshNeo4j.Cast: value #{value} can't be parsed as Regex")
            value
        end

      3 ->
        case Regex.compile(Enum.at(splits, 1), Enum.at(splits, 2)) do
          {:ok, regex} ->
            regex

          {:error, _} ->
            Logger.warning("AshNeo4j.Cast: value #{value} can't be parsed as Regex")
            value
        end

      _ ->
        Logger.warning("AshNeo4j.Cast: value #{value} can't be parsed as Regex")
        value
    end
  end

  defp split_properties(str) do
    {parts, buf, _depths, _in_string} =
      String.graphemes(str)
      |> Enum.reduce({[], "", %{curly: 0, square: 0}, false}, fn
        "\"", {acc, buf, depths, in_string} ->
          {acc, buf <> "\"", depths, !in_string}

        "{", {acc, buf, depths, false} ->
          {acc, buf <> "{", %{depths | curly: depths.curly + 1}, false}

        "}", {acc, buf, depths, false} ->
          {acc, buf <> "}", %{depths | curly: depths.curly - 1}, false}

        "[", {acc, buf, depths, false} ->
          {acc, buf <> "[", %{depths | square: depths.square + 1}, false}

        "]", {acc, buf, depths, false} ->
          {acc, buf <> "]", %{depths | square: depths.square - 1}, false}

        ",", {acc, buf, %{curly: 0, square: 0}, false} ->
          {acc ++ [String.trim(buf)], "", %{curly: 0, square: 0}, false}

        ch, {acc, buf, depths, in_string} ->
          {acc, buf <> ch, depths, in_string}
      end)

    parts ++ [String.trim(buf)]
  end
end
