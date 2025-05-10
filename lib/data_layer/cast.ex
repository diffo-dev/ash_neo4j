defmodule AshNeo4j.DataLayer.Cast do
  @moduledoc "Casting for AshNeo4j.DataLayer"

  @struct_name_regex Regex.compile!("%(.+){.*}")
  @struct_properties_regex Regex.compile!("%.+{(.*)}")

  @doc"""
  Casts an Ash.Resource.Attribute
  """
  def cast(resource, name, value) do
    attribute = Ash.Resource.Info.attribute(resource, name)
    if (value == nil) do
      nil
    else
      if (attribute == nil) do
        IO.puts("warning: cannot cast as name #{name} is not an attribute of resource #{resource}")
        value
      else
        #|> IO.inspect(label: :attribute)
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
            case Keyword.fetch!(attribute.constraints, :casing) do
              :upper -> String.upcase(value)
              :lower -> String.downcase(value)
              nil -> value
            end
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
          _ ->
            IO.puts("warning: no specific cast for type #{inspect(attribute.type)}")
            value
        end
      end
    end
    #|> IO.inspect(label: "cast result")
  end

  defp cast_atom(nil) when is_nil(nil) do
    nil
  end

  defp cast_atom(value) when is_binary(value) do
    String.to_atom(String.replace_leading(value, ":", ""))
  end

  defp cast_function(value) when is_binary(value) do
    [ module_function | arity] = String.replace_leading(value, "&", "") |> String.split("/")
    module_function_splits = String.split(module_function, ".")
    function = List.last(module_function_splits) #|> IO.inspect(label: :function)
    module = Module.concat(module_function_splits |> Enum.reverse() |> tl() |> Enum.reverse) #|> IO.inspect(label: :module)
    Function.capture(module, String.to_atom(function), String.to_integer(hd(arity)))
  end

  defp cast_struct(nil) when is_nil(nil) do
    nil
  end

  defp cast_struct(value) when is_binary(value) do
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
            module = Module.concat([name])
            properties = cast_struct_properties(value)
            struct(module, properties)
        end
    end
  end

  defp struct_name(value) when is_binary(value) do
    Regex.run(@struct_name_regex, value) |> Enum.at(1)
  end

  defp cast_struct_properties(value) when is_binary(value) do
    Regex.run(@struct_properties_regex, value) |> Enum.at(1)
    |> String.split(",") |> Enum.into([], &cast_property(&1))
  end

  defp cast_property(property) when is_binary(property) do
    trimmed = String.trim(property)
    splits = String.split(trimmed, ":")
    key = hd(splits)
    value = Enum.map_join(tl(splits), ":", &String.trim(&1))
    {String.to_atom(key), cast(value)}
  end

  defp cast_datetime(value) when is_bitstring(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, 0} ->
        datetime
      {:error, _message} ->
        IO.puts("warning: value #{value} can't be parsed as DateTime")
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
      "nil" -> nil
      "true" -> true
      "false" -> false
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
                    #IO.puts("warning: value #{value} has leading integer but isn't an integer or float")
                    value
                end
              :error ->
                #IO.puts("warning: no cast for value #{value}")
                value
            end
        end
    end
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
        IO.puts("warning: value #{value} can't be parsed as a Decimal")
        value
    end
  end

  defp cast_regex(value) when is_bitstring(value) do
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
  end
end
