defmodule AshNeo4j.QueryHelper do
  require Logger
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
    cypher =
      cypher(ash_query)
      |> order_by(ash_query)
      |> skip(ash_query)
      |> limit(ash_query)

    case Cypher.run(cypher) do
      {:ok, %Boltx.Response{results: results}} ->
        {:ok, results}

      {:error, _} ->
        {:error, "Error running cypher #{cypher}"}
    end
  end

  defp cypher(ash_query) when is_struct(ash_query) do
    label = Info.label(ash_query.resource)

    if ash_query.filter == nil do
      # there is no filter, but we want related nodes to simulate foreign keys
      "MATCH " <> Cypher.node(:s, [label]) <> " OPTIONAL MATCH (s)-[r]-(d) RETURN s, r, d"
    else
      # will a simple filter work?
      simple_filter = Ash.Filter.to_simple_filter(ash_query.filter, skip_invalid?: true)
      predicates = Map.get(simple_filter, :predicates, [])

      if predicates == [] do
        # simple filter didn't work
        Logger.warning("AshNeo4j.QueryHelper: filter #{inspect(ash_query.filter)} is not a simple filter")
        "MATCH " <> Cypher.node(:s, [label]) <> " OPTIONAL MATCH (s)-[r]-(d) RETURN s, r, d"
      else
        # need to sort out which predicates are source property related, and which are relationship related
        relationship_predicates =
          Enum.reduce(predicates, [], fn predicate, acc ->
            if Map.has_key?(predicate, :operator) do
              operator = convert_operator(predicate.operator)
              property_name = Info.convert_to_property_name(ash_query.resource, predicate.left)
              relationship_name = String.split(property_name, "_") |> List.first()
              node_relationship = Info.node_relationship(ash_query.resource, relationship_name)
              relationship = Ash.Resource.Info.relationship(ash_query.resource, relationship_name)

              if (operator == "in" or operator == "=") and node_relationship != nil and relationship != nil and
                   to_string(relationship.source_attribute) == property_name do
                [predicate | acc]
              else
                acc
              end
            else
              acc
            end
          end)

        property_predicates = predicates -- relationship_predicates

        cond do
          Enum.empty?(relationship_predicates) ->
            "MATCH (s:#{label}) WHERE " <>
              predicates(ash_query.resource, property_predicates) <>
              " OPTIONAL MATCH (s)-[r]-(d) RETURN s, r, d"

          length(relationship_predicates) == 1 ->
            predicate = hd(relationship_predicates)
            operator = convert_operator(predicate.operator)
            property_name = Info.convert_to_property_name(ash_query.resource, predicate.left)
            property_value = convert_value(predicate.right)
            relationship_name = String.split(property_name, "_") |> List.first()
            node_relationship = Info.node_relationship(ash_query.resource, relationship_name)
            relationship = Ash.Resource.Info.relationship(ash_query.resource, relationship_name)
            dest_label = Info.label(relationship.destination)

            dest_property_name =
              Info.convert_to_property_name(relationship.destination, relationship.destination_attribute)

            "MATCH " <>
              Cypher.node(:s, [label]) <>
              Cypher.relationship(node_relationship) <>
              Cypher.node(:d, [dest_label]) <>
              " WHERE " <>
              Cypher.expression(:d, dest_property_name, operator, property_value) <>
              " WITH s MATCH (s)-[r0]-(d0) RETURN s, r0, d0"

          true ->
            Logger.warning("AshNeo4j.QueryHelper: combination of predicates #{inspect(predicates)} not supported")
            "MATCH " <> Cypher.node(:s, [label]) <> " OPTIONAL MATCH (s)-[r]-(d) RETURN s, r, d"
        end
      end
    end
  end

  defp predicates(resource, predicates) when is_atom(resource) and is_list(predicates) do
    Enum.map_join(predicates, " AND ", fn predicate ->
      case predicate do
        %{operator: predicate_operator} ->
          operator = convert_operator(predicate_operator)
          property_name = Info.convert_to_property_name(resource, predicate.left)
          property_value = convert_value(predicate.right)
          Cypher.expression(:s, property_name, operator, property_value)

        %{name: :contains} ->
          argument = hd(predicate.arguments)
          property_name = AshNeo4j.DataLayer.Info.convert_to_property_name(resource, argument)
          attribute = hd(tl(predicate.arguments))
          Cypher.expression(:s, property_name, "contains", attribute)

        _ ->
          Logger.warning("AshNeo4j.QueryHelper: predicate #{inspect(predicate)} not handled")
          "TRUE"
      end
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
  defp convert_operator(:is_nil), do: "is_nil"

  defp convert_operator(operator) do
    Logger.warning("AshNeo4j.QueryHelper: operator #{operator} not handled")
    nil
  end

  defp convert_value(value) when is_binary(value), do: "'#{value}'"

  defp convert_value(value) when is_atom(value), do: "'#{value}'"

  defp convert_value(values) when is_struct(values, MapSet),
    do: "[#{Enum.map(values, fn value -> convert_value(value) end) |> Enum.join(",")}]"

  defp convert_value(value), do: value
end
