defmodule AshNeo4j.DataLayer.Cast do
  @moduledoc "Casting for AshNeo4j.DataLayer"

  @struct_name_regex Regex.compile!("%(.+){.*}")
  @struct_properties_regex Regex.compile!("%.+{(.*)}")

  @doc"""
  Casts an Ash.Resource.Attribute
  """
  def cast(resource, name, value) do
    IO.inspect(name, label: :name)
    IO.inspect(value, label: :value)
    attribute = Ash.Resource.Info.attribute(resource, name) |> IO.inspect(label: :attribute)
    case attribute.type do
      Ash.Type.Atom ->
        String.to_atom(value)
      Ash.Type.Function ->
        # &AshNeo4j.Neo4jHelper.create_node/2
        [ module_function | arity] = String.replace_leading(value, "&", "") |> String.split("/")
        module_function_splits = String.split(module_function, ".")
        function = List.last(module_function_splits) |> IO.inspect(label: :function)
        module = Module.concat(module_function_splits |> Enum.reverse() |> tl() |> Enum.reverse) |> IO.inspect(label: :module)
        Function.capture(module, String.to_atom(function), String.to_integer(hd(arity)))
      Ash.Type.Module ->
        String.to_atom(value)
      Ash.Type.Date ->
        Date.from_iso8601!(value)
      Ash.Type.DateTime ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, 0} ->
            datetime
          {:error, _message} ->
            raise(Ash.Error.Invalid)
        end
      Ash.Type.NaiveDateTime ->
        NaiveDateTime.from_iso8601!(value)
      Ash.Type.Time ->
        Time.from_iso8601!(value)
      Ash.Type.Struct ->
        cast_struct(value)
      Ash.Type.Map ->
        cast_map(value)
      Ash.Type.Decimal ->
        cast_decimal(value)
      _ ->
        IO.puts("warning no specific cast for type #{inspect(attribute.type)}")
        value
    end
    |> IO.inspect(label: "cast result")
  end

  defp cast_struct(nil) when is_nil(nil) do
    nil
  end

  defp cast_struct(value) when is_binary(value) do
    IO.inspect(value, label: "cast_struct value")
    cond do
      String.starts_with?(value, "~r/") ->
        cast_regex(value)
      true ->
        case struct_name(value) do
          "Decimal" ->
            value
          nil ->
            value
          name ->
            IO.inspect(name, label: :name)
            module = Module.concat([name])
            properties = cast_struct_properties(value)
            struct(module, properties)
        end
    end
  end

  defp struct_name(value) when is_binary(value) do
    Regex.run(@struct_name_regex, value) |> Enum.at(1) |> IO.inspect(label: :struct_name)
  end

  defp cast_struct_properties(value) when is_binary(value) do
    Regex.run(@struct_properties_regex, value) |> Enum.at(1)
    |> String.split(",") |> Enum.into([], &cast_property(&1))
  end

  defp cast_property(property) when is_binary(property) do
    whitespace_removed = String.replace(property, " ", "")
    splits = String.split(whitespace_removed, ":")
    key = hd(splits)
    value = Enum.map_join(tl(splits), ":", &String.trim(&1))
    {String.to_atom(key), cast(value)}
  end

  defp cast(value) when is_binary(value) do
    case value do
      "nil" -> nil
      "true" -> true
      "false" -> false
      _ ->
        cond do
          String.starts_with?(value, ":") ->
            String.to_atom(String.replace_leading(value, ":", ""))
          String.starts_with?(value, "\"") && String.ends_with?(value, "\"") ->
            String.replace(value, "\"", "")
          String.starts_with?(value, "[") && String.ends_with?(value, "]") ->
            cast_list(value)
          String.starts_with?(value, "%{") && String.ends_with?(value, "}") ->
            cast_map(value)
          String.starts_with?(value, "%") && String.contains?(value, "{") && String.ends_with?(value, "}") ->
            cast_struct(value)
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
                    IO.puts("warning: value #{value} has leading integer but isn't an integer or float")
                    cast_remaining(value)
                end
              :error ->
                cast_remaining(value)
            end
        end
    end
  end

  defp cast_remaining(value) when is_bitstring(value) do
    value |> IO.inspect(label: :cast_remaining_value)
  end

  defp cast_map(nil) when is_nil(nil) do
    nil
  end

  defp cast_map(value) when is_bitstring(value) do
    value
    |> String.replace_leading("%{", "")
    |> String.replace_trailing("}", "")
    |> String.split(",")
    |> Enum.into(%{}, &cast_property(&1))
  end

  defp cast_list(value) when is_bitstring(value) do
    value
    |> String.replace_leading("[", "")
    |> String.replace_trailing("]", "")
    |> String.split(",")
    |> Enum.into([], &cast_property(&1))
  end

  defp cast_decimal(value) when is_bitstring(value) do
    IO.inspect(value, label: :cast_decimal_value)
    string =
      value
      |> String.replace_leading("Decimal.new(\"", "")
      |> String.replace_trailing("\")", "")
    case Decimal.parse(string) do
      {decimal, _} ->
        decimal
      :error ->
        IO.puts("warning: value #{value} can't be parsed as a Decimal")
        value
    end
    |> IO.inspect(label: :cast_decimal_result)
  end

  defp cast_regex(value) when is_bitstring(value) do
    IO.inspect(value, label: :cast_regex_value)
    splits = String.split(value, "/")
    case length(splits) do
      2 ->
        case Regex.compile(Enum.at(splits, 1)) do
          {:ok, regex} ->
            regex
          {:error, _} ->
            IO.puts("warning: value #{value} can't be parsed as Regex")
            value
        end
      3 ->
        case Regex.compile(Enum.at(splits, 1), Enum.at(splits, 2)) do
          {:ok, regex} ->
            regex
          {:error, _} ->
            IO.puts("warning: value #{value} can't be parsed as Regex")
            value
        end
      _ ->
        IO.puts("warning: value #{value} can't be parsed as Regex")
        value
    end
    |> IO.inspect(label: :cast_regex_result)
  end
end
