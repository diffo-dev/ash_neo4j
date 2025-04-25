defmodule AshNeo4j.Ex4j.Helper do
  require Ash.Query
  use Ex4j.Cypher
  @doc """
  Queries neo4j using Ex4j to return list of Ex4j.Node
  """
  @spec match_nodes(module()) :: list(Ex4j.Node.t())
  def match_nodes(module) when is_atom(module) do
    Code.ensure_loaded(module)
    label = Module.split(module) |> List.last() |> String.to_existing_atom()
    match(module, as: label)
    |> return(label)
    |> run()
  end

  @doc """
  Queries neo4j using Ex4j to return list of Ex4j.Node, using Ash.Query
  """
  @spec match_nodes(module(), term()) :: list(Ex4j.Node.t())
  def match_nodes(module, ash_query) when is_atom(module) do
    #IO.inspect(ash_query, label: "match_nodes ash_query")
    Code.ensure_loaded(module)
    label = Module.split(module) |> List.last() |> String.to_existing_atom()
    query =
      match(module, as: label)
      |> where_from_ash_filter(label, ash_query) #|> IO.inspect(label: "match_nodes where_from_ash_filter")
      |> return(label)
    #IO.inspect(cypher(query), label: "match_nodes cypher")
    query |> run()
  end

  @doc """
  Chains an Ex4j query with a where clause, derived from the Ash.Query.filter
  """
  def where_from_ash_filter(ex4j_query, label, ash_query) do
    if (ash_query.filter == nil) do
      ex4j_query
    else
      simple_filter = Ash.Filter.to_simple_filter(ash_query.filter)
      predicates = Map.get(simple_filter, :predicates, [])
      # TODO handle mulitple predicates
      if (length(predicates) > 1) do
        IO.puts("Multiple predicates, only handling first of: #{inspect(predicates)}")
      end
      predicate = hd(predicates)
      operator = convert_operator(predicate.operator)
      if (operator == nil) do
        IO.puts("Unsupported operator: #{inspect(predicate.operator)}")
        ex4j_query
      else
        property_name = AshNeo4j.DataLayer.Info.convert_to_property_name(ash_query.resource, predicate.left)
        property_value = convert_value(predicate.right)
        ex4j_query
        |> where(label, "#{label}.#{property_name} #{operator} #{property_value}")
      end
    end
  end

  defp convert_operator(:==), do: "="
  defp convert_operator(:!=), do: "<>"
  defp convert_operator(:in), do: "in"
  defp convert_operator(:<=), do: "<="
  defp convert_operator(:<), do: "<"
  defp convert_operator(:>), do: ">"
  defp convert_operator(:>=), do: ">="
  defp convert_operator(_), do: nil

  defp convert_value(value) when is_binary(value), do: "'#{value}'"
  defp convert_value(values) when is_struct(values, MapSet), do: "[#{Enum.map(values, fn value -> convert_value(value) end) |> Enum.join(",")}]"
  defp convert_value(value), do: value
end
