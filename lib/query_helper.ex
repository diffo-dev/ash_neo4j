# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.QueryHelper do
  require Logger

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
    {terms, sort_params} = sort_terms(ash_query, mapping)

    query =
      ash_query
      |> build_query(mapping)
      |> Query.merge_params(sort_params)
      |> Query.paginate_nodes(terms, ash_query.offset, ash_query.limit)
      |> Query.add_order_by(terms)

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

    {terms, sort_params} = sort_terms(ash_query, mapping)

    query =
      branch_queries
      |> Query.combination_block(union_type: union_type)
      |> Query.merge_params(sort_params)
      |> Query.paginate_nodes(terms, ash_query.offset, ash_query.limit)
      |> Query.add_order_by(terms)

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
          {terms, sort_params} = sort_terms(ash_query, mapping)

          final =
            mapping.label_pair
            |> Query.node_read_by_ids(keep_ids)
            |> Query.merge_params(sort_params)
            |> Query.paginate_nodes(terms, ash_query.offset, ash_query.limit)
            |> Query.add_order_by(terms)

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
    case Enum.find(predicates, &traverse_predicate?/1) do
      nil -> build_relationship_or_property_query(mapping, predicates)
      traverse_predicate -> build_traversal_query(mapping, traverse_predicate)
    end
  end

  # A reached-node predicate over a traversal: a field comparison (#321), a
  # field aggregate (#338), or a spatial predicate with the traversal as its
  # geometry argument (#330).
  defp traverse_predicate?(%{left: %AshNeo4j.Functions.Traverse{arguments: [_chain, {agg, field}]}})
       when agg in [:min, :max, :avg, :sum] and is_atom(field),
       do: true

  defp traverse_predicate?(%{left: %AshNeo4j.Functions.Traverse{arguments: [_chain, field]}})
       when is_atom(field),
       do: true

  defp traverse_predicate?(%AshNeo4j.Functions.StDwithin{arguments: [%AshNeo4j.Functions.Traverse{} | _]}), do: true
  defp traverse_predicate?(%AshNeo4j.Functions.StContains{arguments: [%AshNeo4j.Functions.Traverse{} | _]}), do: true
  defp traverse_predicate?(%{left: %AshNeo4j.Functions.StDistance{arguments: [%AshNeo4j.Functions.Traverse{} | _]}}), do: true

  defp traverse_predicate?(%{left: %AshNeo4j.Functions.StDistanceInMeters{arguments: [%AshNeo4j.Functions.Traverse{} | _]}}),
    do: true

  defp traverse_predicate?(_), do: false

  # Membership over the reached set (#334): `traverse(^chain, :exists) == true|false`.
  # `:exists` renders to `EXISTS {}` / `NOT EXISTS {}` — no reached-node field, so
  # no reached-resource typing needed (composes over reverse chains too).
  defp build_traversal_query(%ResourceMapping{} = mapping, %{
         operator: operator,
         left: %AshNeo4j.Functions.Traverse{arguments: [chain, :exists]},
         right: value
       })
       when operator in [:==, :!=] and is_boolean(value) do
    {segments, _reached} = resolve_chain(mapping.module, chain)
    exists? = if operator == :==, do: value, else: not value
    traversal_predicate(mapping, segments, {:exists, exists?})
  end

  # Cardinality over the reached set (#334): `traverse(^chain, :count) <op> n`.
  defp build_traversal_query(%ResourceMapping{} = mapping, %{
         operator: operator,
         left: %AshNeo4j.Functions.Traverse{arguments: [chain, :count]},
         right: value
       })
       when operator in [:==, :!=, :<, :<=, :>, :>=] and is_integer(value) do
    {segments, _reached} = resolve_chain(mapping.module, chain)
    traversal_predicate(mapping, segments, {:count, operator, value})
  end

  # Field aggregate over the reached set (#338): `traverse(^chain, {:min, :field}) <op> value`.
  # Reads `d.field`, so it needs the reached resource's property mapping — a
  # forward relationship-name chain resolves it; a reverse-terminal chain (#336)
  # gives `reached = nil` and falls back to an unfiltered read.
  defp build_traversal_query(%ResourceMapping{} = mapping, %{
         operator: operator,
         left: %AshNeo4j.Functions.Traverse{arguments: [chain, {agg, field}]},
         right: value
       })
       when agg in [:min, :max, :avg, :sum] and operator in [:==, :!=, :<, :<=, :>, :>=] do
    {segments, reached} = resolve_chain(mapping.module, chain)
    traversal_aggregate(mapping, segments, reached, agg, field, operator, value)
  end

  # Reached-node field comparison: `traverse(^chain, :field) <op> value`.
  defp build_traversal_query(%ResourceMapping{} = mapping, %{
         operator: operator,
         left: %AshNeo4j.Functions.Traverse{arguments: [chain, field]},
         right: value
       }) do
    {segments, reached} = resolve_chain(mapping.module, chain)
    condition = {reached_property(reached, field), operator, to_param_value(value), false}
    traversal_query(mapping, segments, [condition])
  end

  # Composition (#330/#332): a spatial predicate with the traversal as its geometry
  # argument — render it against the reached node. Needs a resolvable reached
  # resource (relationship-name chain) for the reached geo attribute.
  defp build_traversal_query(%ResourceMapping{} = mapping, %AshNeo4j.Functions.StDwithin{
         arguments: [%AshNeo4j.Functions.Traverse{arguments: [chain, field]}, test_point, threshold]
       })
       when is_number(threshold) do
    spatial_traversal(mapping, chain, fn reached ->
      {point_property(reached, field), :st_dwithin, {to_geo_param!(reached, field, test_point), threshold}, false}
    end)
  end

  defp build_traversal_query(%ResourceMapping{} = mapping, %{
         operator: operator,
         left: %distance{arguments: [%AshNeo4j.Functions.Traverse{arguments: [chain, field]}, test_point]},
         right: threshold
       })
       when distance in [AshNeo4j.Functions.StDistance, AshNeo4j.Functions.StDistanceInMeters] and is_number(threshold) do
    spatial_traversal(mapping, chain, fn reached ->
      {point_property(reached, field), :st_distance, {operator, to_geo_param!(reached, field, test_point), threshold}, false}
    end)
  end

  defp build_traversal_query(%ResourceMapping{} = mapping, %AshNeo4j.Functions.StContains{
         arguments: [%AshNeo4j.Functions.Traverse{arguments: [chain, field]}, %Geo.Point{} = point]
       }) do
    spatial_traversal(mapping, chain, fn reached ->
      if polygon_attribute?(reached, field) do
        {property_name(reached, field), :st_contains, to_param_value(point), false}
      end
    end)
  end

  # Unsupported traverse predicate shape — fall back to an unfiltered read.
  defp build_traversal_query(%ResourceMapping{} = mapping, _predicate) do
    Logger.debug("AshNeo4j.QueryHelper: unsupported traverse predicate, falling back to node_read")
    Query.node_read(mapping.label_pair)
  end

  # Resolves the chain + reached resource, applies `condition_fn` against the
  # reached mapping (`nil` = not applicable), then builds the traversal read.
  defp spatial_traversal(%ResourceMapping{} = mapping, chain, condition_fn) do
    {segments, reached} = resolve_chain(mapping.module, chain)

    with %ResourceMapping{} = reached_mapping <- reached && ResourceInfo.mapping(reached),
         condition when not is_nil(condition) <- condition_fn.(reached_mapping) do
      traversal_query(mapping, segments, [condition])
    else
      _ ->
        Logger.debug("AshNeo4j.QueryHelper: spatial traverse needs a resolvable reached geo attribute")
        Query.node_read(mapping.label_pair)
    end
  end

  defp traversal_query(%ResourceMapping{} = mapping, [], _conditions) do
    Logger.debug("AshNeo4j.QueryHelper: empty traverse chain")
    Query.node_read(mapping.label_pair)
  end

  defp traversal_query(%ResourceMapping{} = mapping, segments, conditions) do
    Query.traversal_read(mapping.label_pair, segments, conditions)
  end

  defp traversal_predicate(%ResourceMapping{} = mapping, [], _agg) do
    Logger.debug("AshNeo4j.QueryHelper: empty traverse chain")
    Query.node_read(mapping.label_pair)
  end

  defp traversal_predicate(%ResourceMapping{} = mapping, segments, agg) do
    Query.traversal_predicate_read(mapping.label_pair, segments, agg)
  end

  defp traversal_aggregate(%ResourceMapping{} = mapping, [], _reached, _agg, _field, _op, _value) do
    Logger.debug("AshNeo4j.QueryHelper: empty traverse chain")
    Query.node_read(mapping.label_pair)
  end

  # No resolved reached resource (e.g. reverse-terminal chain, #336) — can't map
  # the reached field to a property. Fall back to an unfiltered read.
  defp traversal_aggregate(%ResourceMapping{} = mapping, _segments, nil, _agg, _field, _op, _value) do
    Logger.debug("AshNeo4j.QueryHelper: traverse aggregate needs a resolvable reached field (forward chain)")
    Query.node_read(mapping.label_pair)
  end

  defp traversal_aggregate(%ResourceMapping{} = mapping, segments, reached, agg, field, op, value) do
    prop = property_name(ResourceInfo.mapping(reached), field)
    Query.traversal_aggregate_read(mapping.label_pair, segments, {agg, prop, op, to_param_value(value)})
  end

  # The reached node's property name. With a resolved reached resource we honour
  # its property mapping; for an explicit-edge chain (no resource) we camelCase.
  defp reached_property(nil, field), do: field |> AshNeo4j.Util.to_camel_case() |> to_string()
  defp reached_property(resource, field), do: property_name(ResourceInfo.mapping(resource), field)

  # Resolves a hop chain to `{[{edge_label, direction, dest_label}], reached_resource}`,
  # threading the current resource so relationship-name hops resolve at each step.
  # `reached_resource` is `nil` once an explicit-edge hop breaks the resource chain.
  defp resolve_chain(resource, chain) when is_list(chain) do
    Enum.reduce(chain, {[], resource}, fn hop, {acc, current} ->
      {segment, next} = resolve_hop(current, hop)
      {acc ++ [segment], next}
    end)
  end

  defp resolve_chain(_resource, _), do: {[], nil}

  # Relationship-name hop — resolve via `relate` on the current resource. `:forward`
  # walks the declared edge direction, `:reverse` flips it.
  defp resolve_hop(resource, {direction, rel_name}) when is_atom(rel_name) and not is_nil(resource) do
    case ResourceInfo.node_relationship(resource, rel_name) do
      {_name, edge_label, edge_direction, dest_label} ->
        cypher_direction = if direction == :reverse, do: flip_direction(edge_direction), else: edge_direction
        next = relationship_destination(resource, rel_name)
        dest = if direction == :forward, do: dest_label, else: nil
        {{edge_label, cypher_direction, dest}, next}

      _ ->
        {{rel_name, hop_direction(direction), nil}, nil}
    end
  end

  # Explicit edge hop — `{:edge, label}` or `{:edge, label, dest_label}`.
  defp resolve_hop(_resource, {direction, {:edge, label}}), do: {{label, hop_direction(direction), nil}, nil}
  defp resolve_hop(_resource, {direction, {:edge, label, dest}}), do: {{label, hop_direction(direction), dest}, nil}

  defp relationship_destination(resource, rel_name) do
    case Ash.Resource.Info.relationship(resource, rel_name) do
      %{destination: destination} -> destination
      _ -> nil
    end
  end

  defp hop_direction(:forward), do: :outgoing
  defp hop_direction(:reverse), do: :incoming

  defp flip_direction(:outgoing), do: :incoming
  defp flip_direction(:incoming), do: :outgoing
  defp flip_direction(other), do: other

  defp build_relationship_or_property_query(%ResourceMapping{} = mapping, predicates) do
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
      # st_distance(attr, ^p) <op> ^n and the st_distance_in_meters alias —
      # nested function in comparison, pushed down as point.distance comparison
      # ONLY when attr is a Point attribute (Neo4j point.distance is point-to-point).
      # Point's primary stored value is at "<attr>.point" (the symmetric split
      # introduced in #274 — see Type.Point.primary_suffix/0); the pushdown
      # references that suffixed property, not the bare attribute name.
      %{operator: op, left: %AshNeo4j.Functions.StDistance{arguments: [ref, test_point]}, right: threshold}
      when op in [:<, :<=, :>, :>=, :==, :!=] and is_number(threshold) ->
        if point_attribute?(mapping, ref) do
          prop = point_property(mapping, ref)
          {prop, :st_distance, {op, to_geo_param!(mapping, ref, test_point), threshold}, false}
        end

      %{operator: op, left: %AshNeo4j.Functions.StDistanceInMeters{arguments: [ref, test_point]}, right: threshold}
      when op in [:<, :<=, :>, :>=, :==, :!=] and is_number(threshold) ->
        if point_attribute?(mapping, ref) do
          prop = point_property(mapping, ref)
          {prop, :st_distance, {op, to_geo_param!(mapping, ref, test_point), threshold}, false}
        end

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

      %{name: :st_contains, arguments: [ref, value]} ->
        if polygon_attribute?(mapping, ref) do
          prop = property_name(mapping, ref)

          case value do
            %Geo.Point{} = point ->
              {prop, :st_contains, to_param_value(point), false}

            %Geo.Polygon{} = poly ->
              {prop, :st_contains_box, polygon_bbox_corners(poly), false}

            _other ->
              # other forms — skip pushdown, let in-memory eval handle it
              nil
          end
        end

      %{name: :st_dwithin, arguments: [ref, test_point, threshold]} when is_number(threshold) ->
        if point_attribute?(mapping, ref) do
          prop = point_property(mapping, ref)
          {prop, :st_dwithin, {to_geo_param!(mapping, ref, test_point), threshold}, false}
        end

      %{operator: op, left: %AshNeo4j.Functions.VectorSimilarity{arguments: [ref, query_vec]}, right: threshold}
      when op in [:<, :<=, :>, :>=, :==, :!=] and is_number(threshold) ->
        AshNeo4j.Cypher.require_cypher25!()
        prop = property_name(mapping, ref)
        {prop, :vector_similarity, {op, to_vector_param(query_vec), threshold}, false}

      %{operator: op, left: %AshNeo4j.Functions.VectorCosineDistance{arguments: [ref, query_vec]}, right: threshold}
      when op in [:<, :<=, :>, :>=, :==, :!=] and is_number(threshold) ->
        AshNeo4j.Cypher.require_cypher25!()
        prop = property_name(mapping, ref)
        {prop, :vector_cosine_distance, {op, to_vector_param(query_vec), threshold}, false}

      predicate ->
        Logger.debug("AshNeo4j.QueryHelper: predicate #{inspect(predicate)} not handled")
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  # True when the referenced attribute is a Point-shaped Geo attribute —
  # 2D (`geo_types` includes `:point`) or 3D (`:point_z`, #270). Spatial
  # predicates push down to Neo4j's native `point.distance` / `point.withinBBox`
  # only for Point attributes; other geometries get bbox-prefilter pushdown via
  # their own companions.
  defp point_attribute?(mapping, ref_or_atom) do
    geo_attribute_with_type?(mapping, ref_or_atom, :point) or
      geo_attribute_with_type?(mapping, ref_or_atom, :point_z)
  end

  # Converts a spatial test geometry to a Bolty param, guarding that its
  # coordinate dimension matches the attribute's. Neo4j returns `null` (then
  # silently drops rows) for a 2D/3D mix, so a mismatch raises
  # `AshNeo4j.Error.GeoDimensionMismatch` here instead (#270). Bridge worlds
  # explicitly with `AshNeo4j.Geo.force_2d/1`.
  defp to_geo_param!(mapping, ref, value) do
    types = geo_types_of(mapping, ref)
    vd = value_dim(value)

    cond do
      vd == 3 and :point in types and :point_z not in types ->
        raise AshNeo4j.Error.GeoDimensionMismatch, {2, 3}

      vd == 2 and :point_z in types and :point not in types ->
        raise AshNeo4j.Error.GeoDimensionMismatch, {3, 2}

      true ->
        to_param_value(value)
    end
  end

  defp geo_types_of(%ResourceMapping{module: module}, ref) do
    name = attribute_name(ref)

    case name && Ash.Resource.Info.attribute(module, name) do
      %{constraints: constraints} ->
        case Keyword.get(constraints || [], :geo_types) do
          types when is_list(types) -> types
          type when is_atom(type) -> [type]
          _ -> []
        end

      _ ->
        []
    end
  end

  defp value_dim(%Geo.PointZ{}), do: 3
  defp value_dim(%Geo.Point{}), do: 2
  defp value_dim(%{coordinates: coords}), do: geo_coord_dim(coords)
  defp value_dim(_), do: 2

  defp geo_coord_dim(t) when is_tuple(t), do: tuple_size(t)
  defp geo_coord_dim([head | _]), do: geo_coord_dim(head)
  defp geo_coord_dim(_), do: 2

  # True when the referenced attribute is a Polygon-shaped Geo attribute.
  # st_contains pushdown uses the polygon's bbox companions (`<attr>.bbSW`/
  # `<attr>.bbNE`) for indexed prefilter via `point.withinBBox`.
  defp polygon_attribute?(mapping, ref_or_atom), do: geo_attribute_with_type?(mapping, ref_or_atom, :polygon)

  defp geo_attribute_with_type?(%ResourceMapping{module: module}, ref_or_atom, geo_type) do
    name = attribute_name(ref_or_atom)

    if name do
      case Ash.Resource.Info.attribute(module, name) do
        %{constraints: constraints} ->
          case Keyword.get(constraints || [], :geo_types) do
            types when is_list(types) -> geo_type in types
            ^geo_type -> true
            _ -> false
          end

        _ ->
          false
      end
    else
      false
    end
  end

  # Derives {sw, ne} Bolty Points from a Geo.Polygon's exterior ring,
  # for use in `:st_contains_box` cypher pushdown (two ANDed
  # `point.withinBBox` calls — sufficient for testing whether the
  # polygon's bbox fits inside the attribute's bbox).
  defp polygon_bbox_corners(%Geo.Polygon{coordinates: [exterior | _]}) do
    xs = Enum.map(exterior, &elem(&1, 0))
    ys = Enum.map(exterior, &elem(&1, 1))
    sw = Bolty.Types.Point.create(:wgs_84, Enum.min(xs), Enum.min(ys))
    ne = Bolty.Types.Point.create(:wgs_84, Enum.max(xs), Enum.max(ys))
    {sw, ne}
  end

  defp attribute_name(%Ash.Query.Ref{} = ref), do: Ash.Query.Ref.name(ref)
  defp attribute_name(atom) when is_atom(atom), do: atom
  defp attribute_name(_), do: nil

  # Builds the ORDER BY terms and any params they reference.
  #
  # Returns `{terms, params}` where each term is `{order_expression, :asc | :desc}`
  # with `order_expression` a fully-formed Cypher expression (including the `s.`
  # prefix). Plain properties render to `"s.<prop>"`; a `calc(vector_similarity(…))`
  # or `calc(vector_cosine_distance(…))` sort renders to the corresponding scalar
  # expression with the query embedding bound as a param. Other calculations are
  # dropped (Ash evaluates them in-memory).
  defp sort_terms(ash_query, %ResourceMapping{} = mapping) do
    case ash_query.sort do
      sort when sort in [nil, []] ->
        {[], %{}}

      sort ->
        sort
        |> Enum.with_index()
        |> Enum.reduce({[], %{}}, fn {{name, order}, index}, {terms, params} ->
          case sort_term(mapping, name, order, index) do
            nil -> {terms, params}
            {term, term_params} -> {terms ++ [term], Map.merge(params, term_params)}
          end
        end)
    end
  end

  # vector_similarity / vector_cosine_distance sort — pushed down as the scalar
  # expression, with the query embedding bound as a param.
  defp sort_term(mapping, %Ash.Query.Calculation{module: Ash.Resource.Calculation.Expression, opts: opts}, order, index) do
    case Keyword.get(opts, :expr) do
      %Ash.Query.Call{name: fname, args: [ref, query_vec]} when fname in [:vector_similarity, :vector_cosine_distance] ->
        AshNeo4j.Cypher.require_cypher25!()
        prop = property_name(mapping, ref)
        key = "sort_#{Cypher.sanitize_param(prop)}_#{index}_vec"
        expr = Cypher.vector_scalar(fname, :s, prop, "$#{key}")
        {{expr, order}, %{key => to_vector_param(query_vec)}}

      _ ->
        nil
    end
  end

  # Any other calculation — Ash evaluates it in-memory, so drop from pushdown.
  defp sort_term(_mapping, %Ash.Query.Calculation{}, _order, _index), do: nil

  # Plain property sort.
  defp sort_term(mapping, name, order, _index) do
    prop = Keyword.get(mapping.properties, name, name)
    {{"s.#{prop}", order}, %{}}
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
  defp to_param_value(%Geo.Point{coordinates: {x, y}}), do: Bolty.Types.Point.create(:wgs_84, x, y)
  defp to_param_value(%Geo.PointZ{coordinates: {x, y, z}}), do: Bolty.Types.Point.create(:wgs_84, x, y, z)
  defp to_param_value(value), do: value

  # The query embedding is passed as a plain LIST<FLOAT> param — what
  # `vector.similarity.cosine/2` expects, and consistent with list storage.
  defp to_vector_param(value) when is_list(value), do: Enum.map(value, &(&1 / 1))
  defp to_vector_param(%Bolty.Types.Vector{data: data}), do: Enum.map(data, &(&1 / 1))

  # Builds the on-disk property name for a Point attribute under the symmetric
  # split — `<attr>.point` is where the native Neo4j POINT lives (the indexable
  # primary), so spatial pushdown predicates reference that suffixed name.
  defp point_property(%ResourceMapping{} = mapping, ref) do
    "#{property_name(mapping, ref)}.point"
  end

  defp case_insensitive?(%ResourceMapping{} = mapping, predicate_left, predicate_right) do
    ResourceInfo.attribute_type(mapping.module, predicate_left) in [Ash.Type.CiString, :ci_string] or
      match?(%Ash.CiString{}, predicate_right)
  end
end
