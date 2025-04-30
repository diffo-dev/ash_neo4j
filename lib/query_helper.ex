defmodule AshNeo4j.QueryHelper do
  require Ash.Query

  alias AshNeo4j.Cypher
  alias AshNeo4j.DataLayer.Info

  @moduledoc """
  AshNeo4j Datalayer QueryHelper
  """

  @doc """
  Queries nodes, using Ash.Query
  """
  @spec query_nodes(atom(), term()) :: list(struct())
  def query_nodes(label, ash_query) when is_atom(label) and is_struct(ash_query) do
    cypher = cypher(label, ash_query) #|> IO.inspect(label: "query_nodes cypher")
    case Cypher.run_cypher(cypher) do
      {:ok, %Boltx.Response{results: results}} ->
        results #|> IO.inspect(label: "query_nodes result")
      {:error, _} ->
        throw({:error, "Error running cypher #{cypher}"})
    end
  end

  defp cypher(label, ash_query) when is_atom(label) and is_struct(ash_query) do
    if (ash_query.filter == nil) do
      "MATCH (s:#{label}) RETURN s"
    else
      simple_filter = Ash.Filter.to_simple_filter(ash_query.filter)
      predicates = Map.get(simple_filter, :predicates, [])
      # TODO handle multiple predicates
      if (length(predicates) > 1) do
        IO.puts("Multiple predicates, only handling first of: #{inspect(predicates)}")
      end
      predicate = hd(predicates)
      operator = convert_operator(predicate.operator)
      if (operator == nil) do
        IO.puts("Unsupported operator: #{inspect(predicate.operator)}")
        "MATCH (s:#{label}) RETURN s"
      else
        property_name = Info.convert_to_property_name(ash_query.resource, predicate.left)
        property_value = convert_value(predicate.right) #|> IO.inspect(label: :property_value)
        relationship_name = String.split(property_name, "_") |> List.first() #|> IO.inspect(label: :relationship_name)
        relationship = Ash.Resource.Info.relationship(ash_query.resource, relationship_name)
        # does the query require a related node to be loaded?
        if (operator == "in") && (relationship != nil) && (to_string(relationship.source_attribute) == property_name) do
          # filter is about a related node
          other_label = relationship_name |> String.capitalize() |> String.to_atom()
          other_module = Module.concat(Node, other_label)
          Code.ensure_loaded(other_module)
          other_resource = Info.resource(other_label)
          other_property_name = Info.convert_to_property_name(other_resource, relationship.destination_attribute)
          "MATCH (s:#{label}) -[r:BELONGS_TO]-> (d:#{to_string(other_label)}) WHERE d.#{other_property_name} #{operator} #{property_value} RETURN s, d "
        else
            # filter is about same node, but if the node belongs to other nodes, load them
            "MATCH (s:#{label}) WHERE s.#{property_name} #{operator} #{property_value} OPTIONAL MATCH (s)-[r:BELONGS_TO]-> (d) RETURN s, d"
          #end
        end
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
