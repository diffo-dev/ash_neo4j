# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.QueryHelper do
  require Logger
  require Ash.Query

  alias AshNeo4j.Cypher
  alias AshNeo4j.Cypher.Query
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

    query =
      ash_query
      |> build_query(mapping)
      |> Query.add_order_by(sort_terms(ash_query, mapping))
      |> Query.add_skip(ash_query.offset)
      |> Query.add_limit(ash_query.limit)

    case Cypher.run(query) do
      {:ok, %Bolty.Response{results: results}} ->
        {:ok, results}

      {:error, _} ->
        {:error, "Error running cypher query"}
    end
  end

  defp build_query(ash_query, %ResourceMapping{} = mapping) do
    if ash_query.filter == nil do
      Query.node_read(mapping.label_pair)
    else
      simple_filter = Ash.Filter.to_simple_filter(ash_query.filter, skip_invalid?: true)

      predicates =
        simple_filter
        |> Map.get(:predicates, [])
        |> Enum.reject(fn pred ->
          match?(%Ash.Query.Ref{attribute: %Ash.Query.Calculation{}}, Map.get(pred, :left))
        end)

      if predicates == [] do
        Logger.debug("AshNeo4j.QueryHelper: filter #{inspect(ash_query.filter)} is not a simple filter")
        Query.node_read(mapping.label_pair)
      else
        build_filtered_query(mapping, predicates)
      end
    end
  end

  defp build_filtered_query(%ResourceMapping{} = mapping, predicates) do
    relationship_predicates =
      Enum.filter(predicates, fn predicate ->
        if Map.has_key?(predicate, :operator) and ref_or_atom?(predicate.left) do
          prop = property_name(mapping, predicate.left)
          predicate.operator in [:==, :in] and ResourceInfo.relationship(mapping.module, prop) != nil
        else
          false
        end
      end)

    property_predicates = predicates -- relationship_predicates

    cond do
      Enum.empty?(relationship_predicates) ->
        conditions = to_conditions(mapping, property_predicates)
        Query.node_read_filtered(mapping.label_pair, conditions)

      length(relationship_predicates) == 1 ->
        predicate = hd(relationship_predicates)
        prop = property_name(mapping, predicate.left)
        relationship_name = elem(ResourceInfo.relationship(mapping.module, prop), 1)
        relationship = Ash.Resource.Info.relationship(mapping.module, relationship_name)
        edge = Enum.find(mapping.edges, &(&1.relationship == relationship_name))
        dest_label = ResourceInfo.label(relationship.destination)

        dest_property =
          ResourceInfo.convert_to_property_name(relationship.destination, relationship.destination_attribute)

        Query.relationship_read(
          mapping.label_pair,
          edge.label,
          edge.direction,
          dest_label,
          dest_property,
          predicate.operator,
          to_param_value(predicate.right)
        )

      true ->
        Logger.debug("AshNeo4j.QueryHelper: combination of predicates #{inspect(predicates)} not supported")
        Query.node_read(mapping.label_pair)
    end
  end

  defp to_conditions(%ResourceMapping{} = mapping, predicates) do
    predicates
    |> Enum.map(fn
      # st_distance(prop, ^p) <op> ^n — nested function in comparison; pushed down as point.distance comparison
      %{operator: op, left: %AshNeo4j.Functions.StDistance{arguments: [ref, test_point]}, right: threshold}
      when op in [:<, :<=, :>, :>=, :==, :!=] and is_number(threshold) ->
        prop = property_name(mapping, ref)
        {prop, :st_distance, {op, to_param_value(test_point), threshold}, false}

      %{operator: op, left: left} = predicate when is_struct(left, Ash.Query.Ref) or is_atom(left) ->
        prop = property_name(mapping, predicate.left)
        val = if op == :is_nil, do: predicate.right, else: to_param_value(predicate.right)
        ci? = case_insensitive?(mapping, predicate.left, predicate.right)
        {prop, op, val, ci?}

      %{name: :contains} = predicate ->
        argument = hd(predicate.arguments)
        value = hd(tl(predicate.arguments))
        prop = property_name(mapping, argument)
        ci? = case_insensitive?(mapping, argument, value)
        {prop, :contains, to_param_value(value), ci?}

      %{name: :st_contains} = predicate ->
        argument = hd(predicate.arguments)
        value = hd(tl(predicate.arguments))
        prop = property_name(mapping, argument)

        case to_param_value(value) do
          %Bolty.Types.Point{} = point ->
            {prop, :st_contains, point, false}

          %AshNeo4j.Type.Box{} = box ->
            {prop, :st_contains_box, box, false}

          _other ->
            # other forms — skip pushdown, let in-memory eval handle it
            nil
        end

      %{name: :st_dwithin, arguments: [ref, test_point, threshold]} when is_number(threshold) ->
        prop = property_name(mapping, ref)
        {prop, :st_dwithin, {to_param_value(test_point), threshold}, false}

      predicate ->
        Logger.debug("AshNeo4j.QueryHelper: predicate #{inspect(predicate)} not handled")
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp sort_terms(ash_query, %ResourceMapping{} = mapping) do
    case ash_query.sort do
      sort when sort in [nil, []] ->
        []

      sort ->
        sort
        |> Enum.reject(fn {name, _order} -> is_struct(name, Ash.Query.Calculation) end)
        |> Enum.map(fn {name, order} ->
          {Keyword.get(mapping.properties, name, name), order}
        end)
    end
  end

  defp ref_or_atom?(%Ash.Query.Ref{}), do: true
  defp ref_or_atom?(value) when is_atom(value), do: true
  defp ref_or_atom?(_), do: false

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

  defp case_insensitive?(%ResourceMapping{} = mapping, predicate_left, predicate_right) do
    ResourceInfo.attribute_type(mapping.module, predicate_left) in [Ash.Type.CiString, :ci_string] or
      match?(%Ash.CiString{}, predicate_right)
  end
end
