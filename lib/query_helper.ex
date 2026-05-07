# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.QueryHelper do
  require Logger
  require Ash.Query

  alias AshNeo4j.Cypher
  alias AshNeo4j.Resource.Info, as: ResourceInfo
  alias AshNeo4j.ResourceMapping

  @moduledoc """
  AshNeo4j DataLayer QueryHelper
  """

  @doc """
  Queries nodes, using Ash.Query
  """
  @spec query_nodes(struct()) :: {:error, any()} | {:ok, any()}
  def query_nodes(ash_query) when is_struct(ash_query) do
    mapping = ResourceInfo.mapping(ash_query.resource)

    {cypher, params} =
      ash_query
      |> cypher(mapping)
      |> order_by(ash_query, mapping)
      |> skip(ash_query)
      |> limit(ash_query)

    case Cypher.run(cypher, params) do
      {:ok, %Bolty.Response{results: results}} ->
        {:ok, results}

      {:error, _} ->
        {:error, "Error running cypher #{cypher}"}
    end
  end

  defp cypher(ash_query, %ResourceMapping{} = mapping) do
    base_match = "MATCH " <> Cypher.node(:s, [mapping.label])

    if ash_query.filter == nil do
      {base_match <> " OPTIONAL MATCH (s)-[r]-(d) RETURN s, r, d", %{}}
    else
      simple_filter = Ash.Filter.to_simple_filter(ash_query.filter, skip_invalid?: true)
      predicates = Map.get(simple_filter, :predicates, [])

      if predicates == [] do
        Logger.debug("AshNeo4j.QueryHelper: filter #{inspect(ash_query.filter)} is not a simple filter")
        {base_match <> " OPTIONAL MATCH (s)-[r]-(d) RETURN s, r, d", %{}}
      else
        build_filtered_cypher(mapping, predicates)
      end
    end
  end

  defp build_filtered_cypher(%ResourceMapping{} = mapping, predicates) do
    relationship_predicates =
      Enum.reduce(predicates, [], fn predicate, acc ->
        if Map.has_key?(predicate, :operator) do
          operator = convert_operator(predicate.operator)
          prop_name = property_name(mapping, predicate.left)
          relationship = ResourceInfo.relationship(mapping.module, prop_name)

          if (operator == "IN" or operator == "=") and relationship != nil do
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
        {where_clause, params} = predicates(mapping, property_predicates)
        cypher = "MATCH (s:#{mapping.label}) WHERE #{where_clause} OPTIONAL MATCH (s)-[r]-(d) RETURN s, r, d"
        {cypher, params}

      length(relationship_predicates) == 1 ->
        predicate = hd(relationship_predicates)
        operator = convert_operator(predicate.operator)
        prop_name = property_name(mapping, predicate.left)
        relationship_name = elem(ResourceInfo.relationship(mapping.module, prop_name), 1)
        relationship = Ash.Resource.Info.relationship(mapping.module, relationship_name)
        node_relationship = ResourceInfo.node_relationship(mapping.module, relationship_name)
        dest_label = ResourceInfo.label(relationship.destination)

        dest_property_name =
          ResourceInfo.convert_to_property_name(relationship.destination, relationship.destination_attribute)

        param_key = "d_#{dest_property_name}"

        cypher =
          "MATCH " <>
            Cypher.node(:s, [mapping.label]) <>
            Cypher.relationship(node_relationship) <>
            Cypher.node(:d, [dest_label]) <>
            " WHERE " <>
            Cypher.expression(:d, dest_property_name, operator, "$#{param_key}") <>
            " WITH s MATCH (s)-[r0]-(d0) RETURN s, r0, d0"

        {cypher, %{param_key => to_param_value(predicate.right)}}

      true ->
        Logger.debug("AshNeo4j.QueryHelper: combination of predicates #{inspect(predicates)} not supported")

        {"MATCH " <> Cypher.node(:s, [mapping.label]) <> " OPTIONAL MATCH (s)-[r]-(d) RETURN s, r, d", %{}}
    end
  end

  defp property_name(%ResourceMapping{} = mapping, ref_or_atom) do
    attr_name =
      case ref_or_atom do
        %Ash.Query.Ref{} -> Ash.Query.Ref.name(ref_or_atom)
        atom when is_atom(atom) -> atom
      end

    Keyword.get(mapping.properties, attr_name, attr_name) |> to_string()
  end

  defp to_param_value(%Ash.CiString{} = v), do: Ash.CiString.value(v)
  defp to_param_value(%MapSet{} = ms), do: MapSet.to_list(ms)
  defp to_param_value(value), do: value

  defp predicates(%ResourceMapping{} = mapping, predicates, variable \\ :s) do
    predicates
    |> Enum.with_index()
    |> Enum.reduce({"", %{}}, fn {predicate, index}, {clauses, params_acc} ->
      case predicate do
        %{operator: predicate_operator} ->
          operator = convert_operator(predicate_operator)
          prop_name = property_name(mapping, predicate.left)
          param_key = "#{variable}_#{prop_name}_#{index}"

          clause =
            Cypher.expression(
              variable,
              prop_name,
              operator,
              "$#{param_key}",
              case_insensitive?: case_insensitive?(mapping, predicate.left, predicate.right)
            )

          new_params = Map.put(params_acc, param_key, to_param_value(predicate.right))
          combined = if clauses == "", do: clause, else: "#{clauses} AND #{clause}"
          {combined, new_params}

        %{name: :contains} ->
          argument = hd(predicate.arguments)
          prop_name = property_name(mapping, argument)
          value = hd(tl(predicate.arguments))
          param_key = "#{variable}_#{prop_name}_#{index}"

          clause =
            Cypher.expression(
              variable,
              prop_name,
              "contains",
              "$#{param_key}",
              case_insensitive?: case_insensitive?(mapping, argument, value)
            )

          new_params = Map.put(params_acc, param_key, to_param_value(value))
          combined = if clauses == "", do: clause, else: "#{clauses} AND #{clause}"
          {combined, new_params}

        _ ->
          Logger.debug("AshNeo4j.QueryHelper: predicate #{inspect(predicate)} not handled")
          {if(clauses == "", do: "TRUE", else: "#{clauses} AND TRUE"), params_acc}
      end
    end)
  end

  defp case_insensitive?(%ResourceMapping{} = mapping, predicate_left, predicate_right) do
    ResourceInfo.attribute_type(mapping.module, predicate_left) in [Ash.Type.CiString, :ci_string] or
      match?(%Ash.CiString{}, predicate_right)
  end

  defp order_by({cypher, params}, ash_query, %ResourceMapping{} = mapping)
       when is_bitstring(cypher) and is_struct(ash_query) do
    case ash_query.sort do
      nil ->
        {cypher, params}

      [] ->
        {cypher, params}

      _ ->
        terms =
          Enum.map_join(ash_query.sort, ", ", fn {name, order} ->
            prop = Keyword.get(mapping.properties, name, name)

            case order do
              :desc -> "s.#{prop} DESC"
              _ -> "s.#{prop} ASC"
            end
          end)

        {cypher <> " " <> "ORDER BY " <> terms, params}
    end
  end

  defp limit({cypher, params}, ash_query) when is_bitstring(cypher) and is_struct(ash_query) do
    case ash_query.limit do
      nil -> {cypher, params}
      _ -> {cypher <> " LIMIT #{ash_query.limit}", params}
    end
  end

  defp skip({cypher, params}, ash_query) when is_bitstring(cypher) and is_struct(ash_query) do
    case ash_query.offset do
      nil -> {cypher, params}
      0 -> {cypher, params}
      _ -> {cypher <> " SKIP #{ash_query.offset}", params}
    end
  end

  defp convert_operator(:==), do: "="
  defp convert_operator(:!=), do: "<>"
  defp convert_operator(:in), do: "IN"
  defp convert_operator(:<=), do: "<="
  defp convert_operator(:<), do: "<"
  defp convert_operator(:>), do: ">"
  defp convert_operator(:>=), do: ">="
  defp convert_operator(:is_nil), do: "is_nil"

  defp convert_operator(operator) do
    Logger.debug("AshNeo4j.QueryHelper: operator #{operator} not handled")
    nil
  end
end
