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
  @spec query_nodes(struct()) :: {:error, any()} | {:ok, any()}
  def query_nodes(ash_query) when is_struct(ash_query) do
    cypher = cypher(ash_query) #|> IO.inspect(label: "query_nodes cypher")
    case Cypher.run(cypher) do
      {:ok, %Boltx.Response{results: results}} ->
        {:ok, results}
      {:error, _} ->
        {:error, "Error running cypher #{cypher}"}
    end
    #|> IO.inspect(label: "query_nodes results")
  end

  defp cypher(ash_query) when is_struct(ash_query) do
    label = Info.label(ash_query.resource)
    if (ash_query.filter == nil) do
      "MATCH " <> Cypher.node(:s, label) <> " RETURN s"
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
        "MATCH " <> Cypher.node(:s, label) <> " RETURN s"
      else
        property_name = Info.convert_to_property_name(ash_query.resource, predicate.left) |> IO.inspect(label: :property_name)
        property_value = convert_value(predicate.right) |> IO.inspect(label: :property_value)
        relationship_name = String.split(property_name, "_") |> List.first() |> IO.inspect(label: :relationship_name)
        node_relationship = Info.node_relationship(ash_query.resource, relationship_name) |> IO.inspect(label: :node_relationship)
        relationship = Ash.Resource.Info.relationship(ash_query.resource, relationship_name) |> IO.inspect(label: :relationship)
        # does the query require a related node to be loaded?
        if (operator == "in") && (node_relationship != nil) && (relationship != nil) && (to_string(relationship.source_attribute) == property_name) do
          IO.inspect(ash_query, label: :ash_query)
          # filter is about a destination node
          dest_label = relationship_name |> String.capitalize() |> String.to_atom()
          dest_property_name = Info.convert_to_property_name(relationship.destination, relationship.destination_attribute)
          "MATCH " <> Cypher.node(:s, label) <> Cypher.relationship(node_relationship) <> Cypher.node(:d, dest_label) <> " WHERE " <> Cypher.expression(:d, dest_property_name, operator, property_value) <> " RETURN s, r, d"
          |> IO.inspect(label: :load_related_nodes)
        else
            # filter is about source node but we load other nodes
            #"MATCH (s:#{label}) WHERE s.#{property_name} #{operator} #{property_value} OPTIONAL MATCH (s) -[r]- (d) RETURN s, r, d"
            "MATCH (s:#{label}) WHERE " <> Cypher.expression(:s, property_name, operator, property_value) <> " OPTIONAL MATCH (s)-[r]-(d) RETURN s, r, d"
            |> IO.inspect(label: :load_same_nodes)
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
