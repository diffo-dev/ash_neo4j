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
    case Map.get(ash_query, :combination_of, []) do
      [] -> run_simple_query(ash_query)
      combinations -> run_combination_query(ash_query, combinations)
    end
  end

  defp run_simple_query(ash_query) do
    mapping = ResourceInfo.mapping(ash_query.resource)

    query =
      ash_query
      |> build_query(mapping)
      |> Query.add_order_by(sort_terms(ash_query, mapping))
      |> Query.add_skip(ash_query.offset)
      |> Query.add_limit(ash_query.limit)

    run_cypher_query(query)
  end

  defp run_combination_query(ash_query, combinations) do
    mapping = ResourceInfo.mapping(ash_query.resource)

    case classify_combination(combinations) do
      {:ok, :native, union_type, branch_dl_queries} ->
        run_native_combination(ash_query, mapping, branch_dl_queries, union_type)

      {:ok, :in_memory, all_types, branch_dl_queries} ->
        run_in_memory_combination(ash_query, mapping, branch_dl_queries, all_types)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_native_combination(ash_query, mapping, branch_dl_queries, union_type) do
    branch_queries =
      branch_dl_queries
      |> Enum.with_index()
      |> Enum.map(fn {branch_dl_query, idx} ->
        build_branch_query(branch_dl_query, mapping, "b#{idx}_", :nodes)
      end)

    query =
      branch_queries
      |> Query.combination_block(union_type: union_type)
      |> Query.add_order_by(sort_terms(ash_query, mapping))
      |> Query.add_skip(ash_query.offset)
      |> Query.add_limit(ash_query.limit)

    run_cypher_query(query)
  end

  defp run_in_memory_combination(ash_query, mapping, branch_dl_queries, all_types) do
    branch_id_results =
      branch_dl_queries
      |> Enum.with_index()
      |> Enum.map(fn {branch_dl_query, idx} ->
        query = build_branch_query(branch_dl_query, mapping, "b#{idx}_", :ids)

        case Cypher.run(query) do
          {:ok, %Bolty.Response{results: results}} ->
            {:ok, MapSet.new(results, &Map.get(&1, "sid"))}

          {:error, _} = err ->
            err
        end
      end)

    case Enum.find(branch_id_results, &match?({:error, _}, &1)) do
      nil ->
        [base_set | rest_sets] = Enum.map(branch_id_results, fn {:ok, s} -> s end)
        rest_types = tl(all_types)
        keep_set = apply_set_ops(base_set, Enum.zip(rest_types, rest_sets))
        keep_ids = MapSet.to_list(keep_set)

        if keep_ids == [] do
          {:ok, []}
        else
          final =
            mapping.label_pair
            |> Query.node_read_by_ids(keep_ids)
            |> Query.add_order_by(sort_terms(ash_query, mapping))
            |> Query.add_skip(ash_query.offset)
            |> Query.add_limit(ash_query.limit)

          run_cypher_query(final)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_set_ops(initial_set, []), do: initial_set

  defp apply_set_ops(running_set, [{op, branch_set} | rest]) do
    new_running =
      case op do
        # :union and :union_all are equivalent over id sets — MapSet dedups
        # regardless. The Cypher-level distinction only matters when the
        # native CALL+UNION pushdown path runs.
        :union -> MapSet.union(running_set, branch_set)
        :union_all -> MapSet.union(running_set, branch_set)
        :intersect -> MapSet.intersection(running_set, branch_set)
        :except -> MapSet.difference(running_set, branch_set)
      end

    apply_set_ops(new_running, rest)
  end

  defp run_cypher_query(query) do
    case Cypher.run(query) do
      {:ok, %Bolty.Response{results: results}} ->
        {:ok, results}

      {:error, _} ->
        {:error, "Error running cypher query"}
    end
  end

  # Walks the combination list and decides the execution path.
  # First element must be `:base`. All-`:union` or all-`:union_all` subsequents
  # take the native CALL+UNION pushdown path. Anything else (mixed union types,
  # or any `:intersect` / `:except`) takes the in-memory orchestration path.
  defp classify_combination([{:base, base_query} | rest]) do
    types = Enum.map(rest, &elem(&1, 0))
    branch_queries = [base_query | Enum.map(rest, &elem(&1, 1))]

    cond do
      types == [] ->
        {:ok, :native, :union_all, branch_queries}

      Enum.all?(types, &(&1 == :union)) ->
        {:ok, :native, :union, branch_queries}

      Enum.all?(types, &(&1 == :union_all)) ->
        {:ok, :native, :union_all, branch_queries}

      true ->
        {:ok, :in_memory, [:base | types], branch_queries}
    end
  end

  defp classify_combination(_), do: {:error, "AshNeo4j: combination_of must start with :base"}

  # builder: :nodes | :ids — which branch_node_read variant to use
  defp build_branch_query(branch_dl_query, %ResourceMapping{} = mapping, param_prefix, builder) do
    conditions = extract_branch_conditions(branch_dl_query, mapping)
    build = if builder == :ids, do: &Query.branch_node_read_ids/3, else: &Query.branch_node_read/3
    build.(mapping.label_pair, conditions, param_prefix: param_prefix)
  end

  defp extract_branch_conditions(branch_dl_query, %ResourceMapping{} = mapping) do
    case branch_dl_query.filter do
      nil ->
        []

      filter ->
        simple_filter = Ash.Filter.to_simple_filter(filter, skip_invalid?: true)

        predicates =
          simple_filter
          |> Map.get(:predicates, [])
          |> Enum.reject(fn pred ->
            match?(%Ash.Query.Ref{attribute: %Ash.Query.Calculation{}}, Map.get(pred, :left))
          end)

        to_conditions(mapping, predicates)
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
      # st_distance(prop, ^p) <op> ^n and the st_distance_in_meters alias —
      # nested function in comparison, pushed down as point.distance comparison
      %{operator: op, left: %AshNeo4j.Functions.StDistance{arguments: [ref, test_point]}, right: threshold}
      when op in [:<, :<=, :>, :>=, :==, :!=] and is_number(threshold) ->
        prop = property_name(mapping, ref)
        {prop, :st_distance, {op, to_param_value(test_point), threshold}, false}

      %{operator: op, left: %AshNeo4j.Functions.StDistanceInMeters{arguments: [ref, test_point]}, right: threshold}
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
