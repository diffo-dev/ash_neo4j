defmodule AshNeo4j.QueryHelper do
  require Ash.Query

  alias AshNeo4j.Cypher
  alias AshNeo4j.DataLayer.Info

  @moduledoc """
  AshNeo4j DataLayer QueryHelper
  """

  @doc """
  Queries nodes, using Ash.Query
  """
  @spec query_nodes(struct()) :: {:error, any()} | {:ok, any()}
  def query_nodes(ash_query) when is_struct(ash_query) do
    cypher = cypher(ash_query) |> order_by(ash_query) |> skip(ash_query) |> limit(ash_query)
    # |> IO.inspect(label: :query_nodes_cypher)

    case Cypher.run(cypher) do
      {:ok, %Boltx.Response{results: results}} ->
        {:ok, results}

      {:error, _} ->
        {:error, "Error running cypher #{cypher}"}
    end

    # |> IO.inspect(label: "query_nodes results")
  end

  defp cypher(ash_query) when is_struct(ash_query) do
    label = Info.label(ash_query.resource)

    if ash_query.filter == nil do
      "MATCH " <> Cypher.node(:s, label) <> " RETURN s"
    else
      simple_filter = Ash.Filter.to_simple_filter(ash_query.filter)
      predicates = Map.get(simple_filter, :predicates, [])

      if length(predicates) > 1 do
        # assuming all about source node
        "MATCH (s:#{label}) WHERE " <>
          predicates(ash_query.resource, predicates) <>
          " OPTIONAL MATCH (s)-[r]-(d) RETURN s, r, d"
      else
        # handle a single predicate
        predicate = hd(predicates)

        case predicate do
          %{operator: predicate_operator} ->
            operator = convert_operator(predicate_operator)

            if operator == nil do
              IO.puts("Unsupported operator: #{inspect(predicate.operator)}")
              "MATCH " <> Cypher.node(:s, label) <> " RETURN s"
            else
              property_name =
                Info.convert_to_property_name(ash_query.resource, predicate.left)

              property_value = convert_value(predicate.right)
              relationship_name = String.split(property_name, "_") |> List.first()

              node_relationship =
                Info.node_relationship(ash_query.resource, relationship_name)

              relationship =
                Ash.Resource.Info.relationship(ash_query.resource, relationship_name)

              # does the query require a related node to be loaded?
              if operator == "in" && node_relationship != nil && relationship != nil &&
                   to_string(relationship.source_attribute) == property_name do
                # filter is about a destination node
                dest_label = relationship_name |> String.capitalize() |> String.to_atom()

                dest_property_name =
                  Info.convert_to_property_name(relationship.destination, relationship.destination_attribute)

                "MATCH " <>
                  Cypher.node(:s, label) <>
                  Cypher.relationship(node_relationship) <>
                  Cypher.node(:d, dest_label) <>
                  " WHERE " <> Cypher.expression(:d, dest_property_name, operator, property_value) <> " RETURN s, r, d"
              else
                # filter is about source node but we load other nodes
                # "MATCH (s:#{label}) WHERE s.#{property_name} #{operator} #{property_value} OPTIONAL MATCH (s) -[r]- (d) RETURN s, r, d"
                "MATCH " <>
                  Cypher.node(:s, label) <>
                  " WHERE " <>
                  Cypher.expression(:s, property_name, operator, property_value) <>
                  " OPTIONAL MATCH (s)-[r]-(d) RETURN s, r, d"
              end
            end

          %{name: :contains} ->
            argument = hd(predicate.arguments)
            property_name = AshNeo4j.DataLayer.Info.convert_to_property_name(ash_query.resource, argument)
            attribute = hd(tl(predicate.arguments))

            "MATCH " <>
              Cypher.node(:s, label) <>
              " WHERE " <> Cypher.expression(:s, property_name, "contains", attribute) <> " RETURN s"

          _ ->
            IO.puts("Unsupported predicate: #{inspect(predicate)}")
            "MATCH " <> Cypher.node(:s, label) <> " RETURN s"
        end
      end
    end
  end

  defp predicates(resource, predicates) when is_atom(resource) and is_list(predicates) do
    Enum.map_join(predicates, " AND ", fn predicate ->
      operator = convert_operator(predicate.operator)
      property_name = Info.convert_to_property_name(resource, predicate.left)
      property_value = convert_value(predicate.right)
      Cypher.expression(:s, property_name, operator, property_value)
    end)
  end

  defp order_by(cypher, ash_query) when is_bitstring(cypher) and is_struct(ash_query) do
    case ash_query.sort do
      nil ->
        cypher

      [] ->
        cypher

      _ ->
        translation = AshNeo4j.DataLayer.Info.translation(ash_query.resource)

        terms =
          Enum.map_join(ash_query.sort, ", ", fn {name, order} ->
            case order do
              :desc -> "s.#{Keyword.get(translation, name, name)} DESC"
              _ -> "s.#{Keyword.get(translation, name, name)} ASC"
            end
          end)

        cypher <> " " <> "ORDER BY " <> terms
    end
  end

  defp limit(cypher, ash_query) when is_bitstring(cypher) and is_struct(ash_query) do
    case ash_query.limit do
      nil -> cypher
      _ -> cypher <> " LIMIT #{ash_query.limit}"
    end
  end

  defp skip(cypher, ash_query) when is_bitstring(cypher) and is_struct(ash_query) do
    case ash_query.offset do
      nil -> cypher
      0 -> cypher
      _ -> cypher <> " SKIP #{ash_query.offset}"
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

  defp convert_value(values) when is_struct(values, MapSet),
    do: "[#{Enum.map(values, fn value -> convert_value(value) end) |> Enum.join(",")}]"

  defp convert_value(value), do: value
end
