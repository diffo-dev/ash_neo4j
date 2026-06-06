# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.DataLayer do
  @moduledoc "Ash DataLayer for Neo4j"

  @behaviour Ash.DataLayer

  require Logger
  require AshGeo
  alias AshNeo4j.Resource.Info, as: ResourceInfo
  alias AshNeo4j.ResourceMapping
  alias AshNeo4j.EdgeDescriptor
  alias AshNeo4j.Neo4jHelper
  alias AshNeo4j.QueryHelper
  alias AshNeo4j.Cypher
  alias AshNeo4j.Cypher.Query, as: CypherQuery
  alias AshNeo4j.DataLayer.Cast
  alias AshNeo4j.DataLayer.Dump
  alias AshNeo4j.DataLayer.TypeClassifier
  alias AshNeo4j.Util

  @impl true
  def can?(_, :read), do: true
  def can?(_, :create), do: true
  def can?(_, :composite_primary_key), do: true
  def can?(_, :update), do: true
  def can?(_, :upsert), do: true
  def can?(_, :destroy), do: true
  def can?(_, :sort), do: true
  def can?(_, :filter), do: true
  def can?(_, :limit), do: true
  def can?(_, :offset), do: true
  def can?(_, :boolean_filter), do: true
  def can?(_, {:sort, _}), do: true
  def can?(_, {:join, _}), do: true
  def can?(_, {:lateral_join, _}), do: true
  def can?(_, {:filter_relationship, _}), do: true
  def can?(_, :nested_expressions), do: true

  # Operators with actual Cypher equivalents in convert_operator/1
  def can?(_, {:filter_expr, %Ash.Query.Operator.Eq{}}), do: true
  def can?(_, {:filter_expr, %Ash.Query.Operator.NotEq{}}), do: true
  def can?(_, {:filter_expr, %Ash.Query.Operator.In{}}), do: true
  def can?(_, {:filter_expr, %Ash.Query.Operator.LessThanOrEqual{}}), do: true
  def can?(_, {:filter_expr, %Ash.Query.Operator.LessThan{}}), do: true
  def can?(_, {:filter_expr, %Ash.Query.Operator.GreaterThan{}}), do: true
  def can?(_, {:filter_expr, %Ash.Query.Operator.GreaterThanOrEqual{}}), do: true
  def can?(_, {:filter_expr, %Ash.Query.Operator.IsNil{}}), do: true

  # contains — handled in predicates/2 via the %{name: :contains} branch
  def can?(_, {:filter_expr, %Ash.Query.Function.Contains{}}), do: true

  # spatial — st_contains(box, point) → point.withinBBox pushdown
  def can?(_, {:filter_expr, %AshNeo4j.Functions.StContains{}}), do: true

  # spatial — st_distance(point, point) → point.distance pushdown (in comparisons)
  def can?(_, {:filter_expr, %AshNeo4j.Functions.StDistance{}}), do: true

  # spatial — st_dwithin(point, point, ^km) → point.distance <= ^km pushdown
  def can?(_, {:filter_expr, %AshNeo4j.Functions.StDwithin{}}), do: true

  # spatial parity (in-memory eval) — st_within, st_intersects
  def can?(_, {:filter_expr, %AshNeo4j.Functions.StWithin{}}), do: true
  def can?(_, {:filter_expr, %AshNeo4j.Functions.StIntersects{}}), do: true

  # spatial — st_distance_in_meters: alias for st_distance, same pushdown
  def can?(_, {:filter_expr, %AshNeo4j.Functions.StDistanceInMeters{}}), do: true

  def can?(_, {:filter_expr, %AshNeo4j.Functions.VectorSimilarity{}}), do: true

  # All other filter expressions are accepted so Ash can hydrate and then evaluate
  # them in-memory via filter_stream / RuntimeExpression. Cypher builder falls
  # back to TRUE for unrecognised predicates; filter_stream corrects the results.
  def can?(_, {:filter_expr, _}), do: true

  def can?(_, :transact), do: true
  def can?(_, :expression_calculation), do: true
  def can?(_, {:aggregate, kind}) when kind in [:count, :exists, :sum, :avg, :min, :max, :list, :first], do: true
  def can?(_, {:query_aggregate, kind}) when kind in [:count, :exists, :sum, :avg, :min, :max, :list, :first], do: true
  def can?(_, {:aggregate_relationship, _}), do: true
  # combination queries (#10)
  def can?(_, :combine), do: true
  def can?(_, {:combine, :base}), do: true
  def can?(_, {:combine, :union}), do: true
  def can?(_, {:combine, :union_all}), do: true
  def can?(_, {:combine, :intersect}), do: true
  def can?(_, {:combine, :except}), do: true

  def can?(_, _), do: false

  @impl true
  def functions(_resource) do
    [
      AshNeo4j.Functions.StClosestPoint,
      AshNeo4j.Functions.StContains,
      AshNeo4j.Functions.StDistance,
      AshNeo4j.Functions.StDistanceInMeters,
      AshNeo4j.Functions.StDwithin,
      AshNeo4j.Functions.StIntersects,
      AshNeo4j.Functions.StWithin,
      AshNeo4j.Functions.VectorSimilarity
    ]
  end

  @neo4j %Spark.Dsl.Section{
    name: :neo4j,
    examples: [
      """
      neo4j do
        label :Comment
        relate [{:post, :BELONGS_TO, :outgoing, :Post}]
      end
      """
    ],
    schema: [
      label: [
        type: :atom,
        doc: "Optional node label",
        required: false
      ],
      relate: [
        type: {:list, {:tuple, [:atom, :atom, :atom, :atom]}},
        doc:
          "Optional list of relationships, as tuples of {relationship_name, edge_label, edge_direction, destination_label}",
        required: false,
        default: []
      ],
      guard: [
        type: {:list, {:tuple, [:atom, :atom, :atom]}},
        doc: "Optional list of node relationships, as tuples of {edge_label, edge_direction, destination_label}",
        required: false,
        default: []
      ],
      skip: [
        type: {:list, :atom},
        doc: "Optional list of attributes not to be stored directly as node properties",
        required: false,
        default: []
      ]
    ]
  }

  @impl true
  def limit(query, offset, _), do: {:ok, %{query | limit: offset}}

  @impl true
  def offset(query, offset, _), do: {:ok, %{query | offset: offset}}

  @impl true
  def filter(query, filter, _resource) do
    {:ok, %{query | filter: filter}}
  end

  @impl true
  def sort(query, sort, _resource) do
    deduplicated = Enum.uniq_by(sort, fn {field, _order} -> field end)
    {:ok, %{query | sort: deduplicated}}
  end

  @doc false
  def store_opt(attributes) do
    if Enum.all?(attributes, &is_atom/1) do
      {:ok, attributes}
    else
      {:error, "Expected all attribute names to be atoms"}
    end
  end

  @sections [@neo4j]

  use Spark.Dsl.Extension,
    sections: @sections,
    persisters: [
      AshNeo4j.Persisters.PersistLabels,
      AshNeo4j.Persisters.PersistTranslations,
      AshNeo4j.Persisters.PersistRelationshipAttributes,
      AshNeo4j.Persisters.PersistRelate,
      AshNeo4j.Persisters.PersistMapping
    ],
    verifiers: [
      AshNeo4j.Verifiers.VerifyLabelsPascalCase,
      AshNeo4j.Verifiers.VerifyRelate,
      AshNeo4j.Verifiers.VerifyGuard,
      AshNeo4j.Verifiers.VerifyPropertiesCamelCase,
      AshNeo4j.Verifiers.VerifyEnrichable,
      AshNeo4j.Verifiers.VerifyAttributeType
    ]

  defmodule Query do
    @moduledoc false
    defstruct [
      :resource,
      :sort,
      :filter,
      :limit,
      :offset,
      :domain,
      aggregates: %{},
      calculations: %{},
      combination_of: []
    ]
  end

  @impl true
  @spec run_query(any(), atom()) :: {:error, any()} | {:ok, any()}
  def run_query(query, resource) do
    Logger.debug("""
    AshNeo4j.DataLayer: run_query(#{inspect(query)}, #{inspect(resource)})
    """)

    result =
      case QueryHelper.query_nodes(query) do
        {:error, error} ->
          {:error, error}

        {:ok, []} ->
          {:ok, []}

        {:ok, groups} ->
          all_results =
            convert_groups_to_resources(query, groups)
            |> Enum.to_list()

          case Enum.find(all_results, &match?({:error, _}, &1)) do
            nil ->
              records =
                Enum.map(all_results, fn
                  {:ok, r} -> r
                  r -> r
                end)

              aggregates = Map.values(Map.get(query, :aggregates) || %{})
              calculations = Map.values(Map.get(query, :calculations) || %{})

              with {:ok, records} <- apply_calculations_to_records(records, calculations, resource),
                   records <- filter_matches(records, query.filter, query.domain),
                   {:ok, records} <- apply_aggregates_to_records(records, aggregates, resource) do
                {:ok, apply_calculation_sort(records, query.sort, query.domain)}
              end

            {:error, reason} ->
              {:error, reason}
          end
      end

    Logger.debug("""
    AshNeo4j.DataLayer: run_query result #{inspect(result)}
    """)

    result
  end

  @impl true
  def add_aggregates(query, aggregates, _resource) do
    {:ok, %{query | aggregates: Map.merge(query.aggregates || %{}, Map.new(aggregates, &{&1.name, &1}))}}
  end

  @impl true
  def add_calculation(query, calculation, expression, _resource) do
    calcs = Map.get(query, :calculations) || %{}
    {:ok, %{query | calculations: Map.put(calcs, calculation.name, {calculation, expression})}}
  end

  @impl true
  def run_aggregate_query(data_layer_query, aggregates, resource) do
    mapping = ResourceInfo.mapping(resource)
    pk_field = hd(Ash.Resource.Info.primary_key(resource))
    neo4j_pk = Keyword.get(mapping.properties, pk_field, pk_field)

    case run_query(data_layer_query, resource) do
      {:ok, records} ->
        ids = Enum.map(records, &Map.get(&1, pk_field))

        Enum.reduce_while(aggregates, {:ok, %{}}, fn aggregate, {:ok, acc} ->
          case run_aggregate_for_ids(mapping, neo4j_pk, ids, aggregate, :total) do
            {:ok, value} -> {:cont, {:ok, Map.put(acc, aggregate.name, value)}}
            {:error, e} -> {:halt, {:error, e}}
          end
        end)

      {:error, e} ->
        {:error, e}
    end
  end

  @impl true
  @spec create(atom() | map(), any()) ::
          {:error, <<_::64, _::_*8>> | %{:__exception__ => true, :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, any()}
  def create(resource, changeset) do
    Logger.debug("""
    AshNeo4j.DataLayer: create(#{inspect(resource)}, #{inspect(changeset)})
    """)

    mapping = ResourceInfo.mapping(resource)
    primary_keys = Ash.Resource.Info.primary_key(mapping.module)
    id_attributes = Map.take(changeset.attributes, primary_keys)

    result =
      if Enum.empty?(id_attributes) do
        {:error, "no values supplied for primary keys #{primary_keys}"}
      else
        create_from_attributes(mapping, changeset.attributes)
      end

    Logger.debug("""
    AshNeo4j.DataLayer: create result #{inspect(result)}
    """)

    result
  end

  @impl true
  def upsert(resource, changeset, keys) do
    Logger.debug("""
    AshNeo4j.DataLayer: upsert(#{inspect(resource)}, #{inspect(changeset)}, #{inspect(keys)})
    """)

    mapping = ResourceInfo.mapping(resource)
    id_properties = id_properties(mapping, changeset.attributes)

    result =
      if Enum.any?(Map.values(id_properties), &is_nil(&1)) do
        create(resource, changeset)
      else
        key_filters =
          Enum.map(keys, fn key ->
            {key,
             Ash.Changeset.get_attribute(changeset, key) || Map.get(changeset.params, key) ||
               Map.get(changeset.params, to_string(key))}
          end)

        query = Ash.Query.do_filter(resource, and: [key_filters])

        resource
        |> resource_to_query(changeset.domain)
        |> Map.put(:filter, query.filter)
        |> Map.put(:tenant, changeset.tenant)
        |> run_query(resource)
        |> case do
          {:ok, []} ->
            create(resource, changeset)

          {:ok, [result]} ->
            to_set = Ash.Changeset.set_on_upsert(changeset, keys)

            changeset =
              changeset
              |> Map.put(:attributes, %{})
              |> Map.put(:data, result)
              |> Ash.Changeset.force_change_attributes(to_set)

            update(resource, changeset)

          {:ok, _} ->
            {:error, "Multiple records matching keys"}
        end
      end

    Logger.debug("""
    AshNeo4j.DataLayer: upsert result #{inspect(result)}
    """)

    result
  end

  @impl true
  def update(resource, changeset) do
    Logger.debug("""
    AshNeo4j.DataLayer: update(#{inspect(resource)}, #{inspect(changeset)}})
    """)

    mapping = ResourceInfo.mapping(resource)
    subject_id = id_properties(mapping, changeset.data)
    subject_label = mapping.label_pair

    update_properties = dump_properties(mapping, changeset.attributes)

    remove_property_names = stale_property_names(mapping, update_properties, changeset)

    property_update_result =
      if !Enum.empty?(update_properties) or !Enum.empty?(remove_property_names) do
        case subject_label |> Neo4jHelper.update_node(subject_id, update_properties, remove_property_names) do
          {:ok, %Bolty.Response{results: []}} ->
            {:error, "no result to update node"}

          {:ok, %Bolty.Response{results: [node_map | _]}} ->
            node = Map.get(node_map, "n")
            convert_node_to_resource(resource, node)

          {:error, error} ->
            {:error, error}
        end
      end

    relationship_update_result =
      if accessing_from = Map.get(changeset.context, :accessing_from) do
        object_resource = Map.get(accessing_from, :source)
        object_label = ResourceInfo.label(object_resource)
        object_relationship_name = Map.get(accessing_from, :name)
        object_node_relationship = ResourceInfo.node_relationship(object_resource, object_relationship_name)

        if Map.get(accessing_from, :unrelating?) do
          object_id =
            relationship_properties(resource, object_resource, changeset.data, object_relationship_name)

          case map_size(object_id) do
            0 ->
              {:error, "couldn't unrelate nodes"}

            _ ->
              {_relationship_name, edge_label, object_to_subject_direction, _destination_label} =
                object_node_relationship

              case Neo4jHelper.unrelate_nodes(
                     subject_label,
                     subject_id,
                     object_label,
                     object_id,
                     edge_label,
                     Util.reverse(object_to_subject_direction)
                   ) do
                {:ok, %Bolty.Response{results: []}} ->
                  {:error, "no result to unrelate nodes"}

                {:ok, %Bolty.Response{results: [node_map | _]}} ->
                  node = Map.get(node_map, "s")
                  convert_node_to_resource(resource, node)

                {:error, error} ->
                  {:error, error}
              end
          end
        else
          object_id = relationship_properties(resource, object_resource, changeset.attributes, object_relationship_name)

          case map_size(object_id) do
            0 ->
              {:error, "couldn't relate nodes"}

            _ ->
              {_relationship_name, edge_label, object_to_subject_direction, _object_label} = object_node_relationship

              case Neo4jHelper.relate_nodes(
                     subject_label,
                     subject_id,
                     object_label,
                     object_id,
                     edge_label,
                     Util.reverse(object_to_subject_direction)
                   ) do
                {:ok, %Bolty.Response{results: []}} ->
                  {:error, "no result to relate nodes"}

                {:ok, %Bolty.Response{results: [node_map | _]}} ->
                  node = Map.get(node_map, "s")
                  convert_node_to_resource(resource, node)

                {:error, error} ->
                  {:error, error}
              end
          end
        end
      else
        if changeset.relationships do
          Enum.reduce_while(changeset.relationships, nil, fn {relationship_name, relationship_change}, _acc ->
            subject_edge = Enum.find(mapping.edges, &(&1.relationship == relationship_name))

            subject_relationship =
              Ash.Resource.Info.relationship(resource, relationship_name)

            object_resource = subject_relationship.destination
            object_label = ResourceInfo.label(object_resource)

            {arguments, options} = hd(relationship_change)
            type = Keyword.get(options, :type)

            cond do
              arguments == [] or type == :remove ->
                subject_source_attribute = subject_relationship.source_attribute
                subject_destination_attribute = subject_relationship.destination_attribute

                object_property_name =
                  ResourceInfo.convert_to_property_name(object_resource, subject_destination_attribute)

                object_property_value = Map.get(changeset.data, subject_source_attribute)
                object_id = %{object_property_name => object_property_value}

                case map_size(object_id) do
                  0 ->
                    {:halt, {:error, "couldn't unrelate nodes"}}

                  _ ->
                    case Neo4jHelper.unrelate_nodes(
                           subject_label,
                           subject_id,
                           object_label,
                           object_id,
                           subject_edge.label,
                           subject_edge.direction
                         ) do
                      {:ok, %Bolty.Response{results: []}} ->
                        {:halt, {:error, "no result to unrelate nodes"}}

                      {:ok, %Bolty.Response{results: [node_map | _]}} ->
                        node = Map.get(node_map, "s")

                        case convert_node_to_resource(resource, node) do
                          {:ok, resource} -> {:cont, {:ok, resource}}
                          {:error, reason} -> {:halt, {:error, reason}}
                        end

                      {:error, error} ->
                        {:halt, {:error, error}}
                    end
                end

              true ->
                arg_relate_result =
                  Enum.reduce_while(arguments, nil, fn argument, _acc ->
                    object_id = ResourceInfo.convert_to_properties(object_resource, argument)

                    case map_size(object_id) do
                      0 ->
                        {:halt, {:error, "couldn't relate nodes using argument"}}

                      _ ->
                        subject_exclusive? = ResourceInfo.source_exclusive?(resource, relationship_name)
                        object_exclusive? = ResourceInfo.destination_exclusive?(resource, relationship_name)

                        case Neo4jHelper.relate_nodes(
                               subject_label,
                               subject_id,
                               object_label,
                               object_id,
                               subject_edge.label,
                               subject_edge.direction,
                               {subject_exclusive?, object_exclusive?}
                             ) do
                          {:ok, %Bolty.Response{results: []}} ->
                            {:halt, {:error, "no result to relate nodes"}}

                          {:ok, %Bolty.Response{results: [node_map | _]}} ->
                            node = Map.get(node_map, "s")

                            case convert_node_to_resource(resource, node) do
                              {:ok, resource} -> {:cont, {:ok, resource}}
                              {:error, reason} -> {:halt, {:error, reason}}
                            end

                          {:error, error} ->
                            {:halt, {:error, error}}
                        end
                    end
                  end)

                case arg_relate_result do
                  {:error, _} ->
                    {:halt, arg_relate_result}

                  {:ok, _} ->
                    {:cont, arg_relate_result}
                end
            end
          end)
        else
          {:error, "changeset not handled"}
        end
      end

    result = relationship_update_result || property_update_result

    Logger.debug("""
    AshNeo4j.DataLayer: update result #{inspect(result)}
    """)

    result
  end

  @impl true
  def destroy(resource, changeset) do
    Logger.debug("""
    AshNeo4j.DataLayer: destroy(#{inspect(resource)}, #{inspect(changeset)}})
    """)

    mapping = ResourceInfo.mapping(resource)
    label = mapping.label_pair
    id_properties = id_properties(mapping, changeset.data)

    result =
      case Neo4jHelper.safe_delete_nodes(label, id_properties, ResourceInfo.preserve_node_relationships(resource)) do
        {:ok, _} ->
          :ok

        {:error, "nothing deleted"} ->
          {:error,
           Ash.Error.Invalid.Unavailable.exception(
             resource: resource,
             source: AshNeo4j.DataLayer,
             reason: "guarded relationships prevent deletion"
           )}

        {:error, error} ->
          {:error, error}
      end

    Logger.debug("AshNeo4j.DataLayer: delete result #{inspect(result)}")

    result
  end

  @impl true
  def resource_to_query(resource, domain) do
    %Query{resource: resource, domain: domain}
  end

  @impl true
  def combination_of(combinations, resource, domain) do
    {:ok, %Query{resource: resource, domain: domain, combination_of: combinations}}
  end

  @impl true
  def transaction(resource, fun, _timeout, _) do
    label = ResourceInfo.label(resource)

    if AshNeo4j.Sandbox.active?() do
      prev = Process.get(:ash_neo4j_in_sandbox_tx, false)
      Process.put(:ash_neo4j_in_sandbox_tx, true)
      Process.put({:neo4j_in_transaction, label}, true)

      try do
        case fun.() do
          {:error, error} -> {:error, error}
          result -> {:ok, result}
        end
      catch
        {{:neo4j_rollback, _}, value} -> {:error, value}
      after
        Process.put(:ash_neo4j_in_sandbox_tx, prev)
        Process.delete({:neo4j_in_transaction, label})
      end
    else
      Bolty.transaction(Bolt, fn conn ->
        stack = Process.get(:ash_neo4j_tx_stack, [])
        Process.put(:ash_neo4j_tx_stack, [conn | stack])
        Process.put({:neo4j_in_transaction, label}, true)

        try do
          case fun.() do
            {:error, error} -> Bolty.rollback(conn, error)
            result -> result
          end
        catch
          {{:neo4j_rollback, _}, value} -> Bolty.rollback(conn, value)
        after
          Process.put(:ash_neo4j_tx_stack, stack)
          Process.delete({:neo4j_in_transaction, label})
        end
      end)
    end
  end

  @impl true
  def rollback(resource, error) do
    throw({{:neo4j_rollback, ResourceInfo.label(resource)}, error})
  end

  @impl true
  def in_transaction?(_resource) do
    Process.get(:ash_neo4j_tx_stack, []) != [] or
      Process.get(:ash_neo4j_in_sandbox_tx, false)
  end

  defp filter_matches(records, nil, _domain), do: records

  defp filter_matches(records, filter, domain) do
    {:ok, records} = Ash.Filter.Runtime.filter_matches(domain, records, filter)
    records
  end

  # Reads the on-disk property value for an attribute, handling the geo
  # path specially: for `:geo` classified attributes the canonical lives
  # at `<attr>.json` as an RFC 7946 GeoJSON STRING, which we decode here
  # so Cast just sees the resulting %Geo.*{} struct and dispatches it
  # through standard `:ash` (AshGeo's identity cast_stored).
  defp read_attribute_property(resource, resource_field, node_field, properties) do
    base = to_string(node_field)

    case Ash.Resource.Info.attribute(resource, resource_field) do
      %{type: type} ->
        attribute_type = Ash.Type.get_type!(type)

        case TypeClassifier.classify(attribute_type) do
          {:ok, :geo, _} ->
            case Map.get(properties, "#{base}.json") do
              nil -> nil
              json when is_binary(json) -> AshNeo4j.GeoJson.decode!(json)
            end

          _ ->
            Map.get(properties, base)
        end

      _ ->
        Map.get(properties, base)
    end
  end

  defp consolidate_groups(groups) when is_list(groups) do
    Enum.reduce(groups, [], fn group, acc ->
      s = Map.get(group, "s")
      tuple_count = Integer.floor_div(Enum.count(group), 2)

      tuples =
        Enum.reduce(0..(tuple_count - 1)//1, [], fn tuple, acc ->
          r = Map.get(group, "r#{tuple}") || Map.get(group, "r")
          d = Map.get(group, "d#{tuple}") || Map.get(group, "d")

          cond do
            r != nil && d != nil ->
              [{r, d} | acc]

            true ->
              acc
          end
        end)

      cond do
        [] == acc ->
          [{s, tuples}]

        [previous | tail] = acc ->
          cond do
            Map.get(s, :id) == elem(previous, 0).id ->
              cond do
                tuples == [] ->
                  acc

                true ->
                  [{s, tuples ++ elem(previous, 1)} | tail]
              end

            true ->
              [{s, tuples} | acc]
          end
      end
    end)
    |> Enum.into(
      [],
      fn group ->
        {source, related} = group
        {source, Enum.reverse(related)}
      end
    )
    |> Enum.reverse()
  end

  defp convert_groups_to_resources(query, groups) when is_struct(query, Query) and is_list(groups) do
    mapping = ResourceInfo.mapping(query.resource)

    consolidate_groups(groups)
    |> Stream.map(&convert_to_resource(query, mapping, &1))
  end

  defp convert_to_resource(query, %ResourceMapping{} = mapping, consolidated_group)
       when is_struct(query, Query) and is_tuple(consolidated_group) do
    source_node = elem(consolidated_group, 0)
    related = elem(consolidated_group, 1)

    enrichments =
      Enum.reduce(related, [], &enrichments(mapping, &2, &1))
      |> consolidate_enrichments()

    convert_node_to_resource(mapping, source_node, enrichments)
  end

  defp consolidate_enrichments(enrichments) when is_list(enrichments) do
    Enum.reduce(enrichments, [], fn enrichment, acc ->
      case enrichment do
        {name, value} ->
          cond do
            [] == acc ->
              [enrichment]

            [head | tail] = acc ->
              cond do
                name == elem(head, 0) and is_list(value) and is_list(elem(head, 1)) ->
                  merged_value = [hd(value) | elem(head, 1)]
                  [{name, merged_value} | tail]

                true ->
                  [enrichment | acc]
              end
          end

        nil ->
          acc
      end
    end)
  end

  defp enrichments(%ResourceMapping{} = mapping, acc, {edge, dest_node})
       when is_list(acc) and is_map(edge) and is_map(dest_node) do
    dest_labels = Enum.into(dest_node.labels, [], &String.to_atom(&1))
    edge_label = String.to_atom(edge.type)
    edge_direction = edge_direction(edge, dest_node)

    dest_labels_filtered = List.delete(dest_labels, mapping.domain_label)

    relationship =
      Enum.find_value(dest_labels_filtered, fn dest_label ->
        case Enum.find(mapping.edges, fn ed ->
               ed.label == edge_label and ed.direction == edge_direction and
                 ed.destination_label == dest_label
             end) do
          nil -> nil
          ed -> Ash.Resource.Info.relationship(mapping.module, ed.relationship)
        end
      end)

    if relationship != nil do
      reverse_node_relationship = ResourceInfo.reverse_node_relationship(mapping.module, relationship.name)

      reverse_relationship =
        if reverse_node_relationship != nil do
          Ash.Resource.Info.relationship(relationship.destination, elem(reverse_node_relationship, 0))
        end

      cond do
        relationship.cardinality == :one && relationship.type == :belongs_to ->
          destination_property =
            ResourceInfo.convert_to_property_name(relationship.destination, relationship.destination_attribute)

          [
            {relationship.source_attribute, Map.get(dest_node.properties, destination_property)} | acc
          ]

        reverse_relationship != nil &&
            (reverse_relationship.cardinality == :one && reverse_relationship.type == :has_one) ->
          source_property =
            Keyword.get(mapping.properties, relationship.source_attribute, relationship.source_attribute)
            |> to_string()

          [
            {relationship.destination_attribute, Map.get(dest_node.properties, source_property)} | acc
          ]

        relationship.cardinality == :many && reverse_relationship != nil && reverse_relationship.cardinality == :many ->
          case convert_node_to_resource(relationship.destination, dest_node, []) do
            {:ok, dest_resource} ->
              [{relationship.name, [dest_resource]} | acc]

            {:error, reason} ->
              Logger.debug("AshNeo4j.DataLayer: unable to convert enrichment node: #{inspect(reason)}")
              acc
          end

        true ->
          acc
      end
    else
      acc
    end
  end

  defp edge_direction(edge, dest_node) when is_map(edge) and is_map(dest_node) do
    cond do
      dest_node.id == edge.start ->
        :incoming

      dest_node.id == edge.end ->
        :outgoing

      true ->
        nil
    end
  end

  defp convert_node_to_resource(subject, node, enrichments \\ [])

  defp convert_node_to_resource(%ResourceMapping{} = mapping, node, enrichments)
       when is_map(node) and is_list(enrichments) do
    convert_node_to_resource_impl(mapping.module, mapping.properties, node, enrichments)
  end

  defp convert_node_to_resource(resource, node, enrichments)
       when is_atom(resource) and is_map(node) and is_list(enrichments) do
    convert_node_to_resource_impl(resource, ResourceInfo.translations(resource), node, enrichments)
  end

  defp convert_node_to_resource_impl(resource, translations, node, enrichments)
       when is_atom(resource) and is_list(translations) and is_map(node) and is_list(enrichments) do
    enriched = Enum.into(enrichments, %{}, fn {field, value} -> {field, value} end)

    fields_result =
      Enum.reduce_while(translations, {:ok, enriched}, fn {resource_field, node_field}, {:ok, acc} ->
        property_value = read_attribute_property(resource, resource_field, node_field, node.properties)

        case cast_attribute(resource, resource_field, property_value) do
          {:ok, value} -> {:cont, {:ok, Map.put(acc, resource_field, value)}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case fields_result do
      {:error, reason} ->
        {:error, reason}

      {:ok, fields} ->
        belongs_to =
          Ash.Resource.Info.relationships(resource)
          |> Enum.filter(fn relationship ->
            relationship.type == :belongs_to and relationship.allow_nil?
          end)

        nilled_fields =
          Enum.reduce(belongs_to, fields, fn relationship, acc ->
            if Map.get(fields, relationship.source_attribute) == nil do
              acc |> Map.put(relationship.name, nil)
            else
              acc
            end
          end)

        {:ok,
         struct!(resource, nilled_fields)
         |> Ash.Resource.set_metadata(%{node_id: node.id, data_layer: __MODULE__, labels: node.labels})
         |> Ash.Resource.set_meta(struct(Ecto.Schema.Metadata, state: :loaded))}
    end
  end

  defp create_from_attributes(%ResourceMapping{} = mapping, attributes) when is_map(attributes) do
    properties = dump_properties(mapping, attributes)

    case create_node(mapping, properties) do
      {:ok, source_resource} ->
        relate_nodes(source_resource, mapping.module, attributes, mapping)

      {:error, error} ->
        {:error, error}
    end
  end

  defp relate_nodes(source_resource, resource, attributes, %ResourceMapping{} = mapping)
       when is_struct(source_resource) and is_atom(resource) and is_map(attributes) do
    relationship_attributes = mapping.relationship_attributes |> Keyword.delete(:id)
    relationship_source_attributes = Map.take(attributes, Keyword.keys(relationship_attributes))

    case Enum.count(relationship_source_attributes) do
      0 ->
        {:ok, source_resource}

      _ ->
        relationships =
          relationship_attributes
          |> Enum.reduce(
            [],
            fn {source_attribute, name}, acc ->
              relationship = Ash.Resource.Info.relationship(resource, name)
              dest_resource = relationship.destination

              case Enum.find(mapping.edges, &(&1.relationship == name)) do
                nil ->
                  acc

                %EdgeDescriptor{label: edge_label, direction: edge_direction, destination_label: destination_label} ->
                  dest_node_property_name =
                    Keyword.get(ResourceInfo.translations(dest_resource), relationship.destination_attribute)

                  dest_id_value = Map.get(relationship_source_attributes, source_attribute)

                  if dest_id_value == nil do
                    acc
                  else
                    dest_id = %{dest_node_property_name => dest_id_value}
                    exclusive = ResourceInfo.destination_exclusive?(resource, name)
                    [{destination_label, dest_id, edge_label, edge_direction, exclusive} | acc]
                  end
              end
            end
          )

        label = mapping.label_pair
        id_properties = id_properties(mapping, attributes)

        case Neo4jHelper.relate_nodes(label, id_properties, relationships) do
          :ok ->
            case Neo4jHelper.read_nodes_related(label, id_properties) do
              {:ok, %Bolty.Response{results: groups}} ->
                consolidated_groups = consolidate_groups(groups)

                cond do
                  length(consolidated_groups) == 1 ->
                    query = resource_to_query(resource, Ash.Resource.Info.domain(resource))
                    convert_to_resource(query, mapping, hd(consolidated_groups))

                  true ->
                    {:error, "expected groups to consolidate to a single group (resource)"}
                end

              {:error, error} ->
                {:error, error}
            end

          {:error, error} ->
            {:error, error}
        end
    end
  end

  defp create_node(%ResourceMapping{} = mapping, properties) when is_map(properties) do
    case mapping.all_labels |> Neo4jHelper.create_node(properties) do
      {:ok, %Bolty.Response{results: [node_map | _]}} ->
        node = Map.get(node_map, "n")
        convert_node_to_resource(mapping.module, node)

      {:error, error} ->
        {:error, error}
    end
  end

  defp id_properties(%ResourceMapping{} = mapping, map) when is_map(map) do
    primary_keys = Ash.Resource.Info.primary_key(mapping.module)
    Enum.into(primary_keys, %{}, fn key -> {Keyword.get(mapping.properties, key, key), Map.get(map, key)} end)
  end

  defp relationship_properties(source_resource, dest_resource, source_map, dest_relationship_name)
       when is_atom(source_resource) and is_atom(dest_resource) and is_map(source_map) and
              is_atom(dest_relationship_name) do
    source_node_relationship = ResourceInfo.reverse_node_relationship(dest_resource, dest_relationship_name)

    if source_node_relationship != nil do
      source_relationship_name = elem(source_node_relationship, 0)
      source_relationship = Ash.Resource.Info.relationship(source_resource, source_relationship_name)
      value = Map.get(source_map, source_relationship.source_attribute)

      if value != nil do
        dest_property_name =
          ResourceInfo.convert_to_property_name(dest_resource, source_relationship.destination_attribute)
          |> String.to_atom()

        %{dest_property_name => value}
      else
        %{}
      end
    else
      %{}
    end
  end

  # Property names to REMOVE on update: those the OLD value of each changed
  # attribute occupied that the NEW value no longer writes. Diffing the dumped
  # property KEYS of old vs new keeps removal exactly consistent with the write
  # path (dump_properties/2), and covers every companion-shape mismatch with one
  # mechanism:
  #
  #   * cleared to nil           — the new value writes nothing, so every old key
  #                                goes, including geo companions (#283)
  #   * geometry kind changed    — a Point's `<attr>.point` and an area's
  #                                `<attr>.bbSW`/`<attr>.bbNE` swap out (#287)
  #   * nested geo added/removed — dotted `<attr>.<path>.point|bbSW|bbNE`
  #                                companions the new value no longer promotes (#287)
  #
  # Only changed attributes are considered (unchanged ones keep their companions).
  # REMOVE of an absent property is a no-op; a key present in both old and new is
  # left in place for SET (`n += {…}`) to overwrite.
  defp stale_property_names(%ResourceMapping{} = mapping, new_properties, changeset)
       when is_map(new_properties) do
    old_properties =
      dump_properties(mapping, Map.take(changeset.data, Map.keys(changeset.attributes)))

    Map.keys(old_properties) -- Map.keys(new_properties)
  end

  def cast_attribute(_resource, _name, nil) do
    {:ok, nil}
  end

  def cast_attribute(resource, name, value) when is_atom(resource) and is_atom(name) do
    attribute = Ash.Resource.Info.attribute(resource, name)

    if attribute == nil do
      Logger.debug(
        "AshNeo4j.DataLayer: no attribute found for resource #{inspect(resource)} and name #{inspect(name)}, returning original value"
      )

      {:ok, value}
    else
      Cast.cast(attribute.type, value, attribute.constraints)
    end
  end

  defp dump_properties(%ResourceMapping{} = mapping, attributes) when is_map(attributes) do
    mapping.properties
    |> Enum.reduce(%{}, fn {key, translated_key}, acc ->
      value = Map.get(attributes, key)

      if value != nil do
        attribute = Ash.Resource.Info.attribute(mapping.module, key)

        attribute_type =
          Ash.Type.get_type!(attribute.type)

        dumped = Dump.dump(attribute_type, value, attribute.constraints)

        case TypeClassifier.classify(attribute_type) do
          {:ok, :geo, _} ->
            # Geo attribute: AshGeo's identity dump_to_native returned the
            # %Geo.*{} struct unchanged. Promote it into RFC 7946 JSON
            # canonical at <attr>.json + indexable companions (a native
            # Neo4j Point at <attr>.point for Geo.Point, or scalar
            # bbSW/bbNE for other geometries).
            promote_geo(acc, translated_key, dumped)

          _ ->
            # Non-geo: dumped goes at the bare translated key.
            acc = Map.put(acc, translated_key, dumped)

            # Recursive geo-promotion: walk the *input* value (not the
            # dumped form, which may have been JSON-stringified) for any
            # nested %Geo.*{} structs and promote each one's indexable
            # companion to the node at its path. The canonical GeoJSON
            # for the nested geo lives inside the parent's JSON blob —
            # we only emit the indexable sidecar here. Path joining is
            # dotted (`<attr>.<field>...`) for namespace clarity.
            value
            |> geo_walk([translated_key])
            |> Enum.reduce(acc, fn {path, geo}, inner_acc ->
              promote_geo_indexable(inner_acc, Enum.join(path, "."), geo)
            end)
        end
      else
        acc
      end
    end)
  end

  # Promotes a %Geo.*{} struct into the **full** on-disk shape: RFC 7946
  # GeoJSON STRING canonical at <attr>.json + an indexable companion sized
  # to the geometry kind. Point gets a native Neo4j Point at <attr>.point
  # (preserves point.distance / point.withinBBox server-side pushdown);
  # any other geometry gets scalar bbSW/bbNE Points derived from the
  # bounding box (useful for bbox-prefilter pushdown).
  #
  # Used for top-level Geo attributes — the canonical lives at
  # <attr>.json because there's no enclosing JSON blob to nest inside.
  defp promote_geo(acc, translated_key, geo) do
    acc
    |> Map.put("#{translated_key}.json", AshNeo4j.GeoJson.encode!(geo))
    |> promote_geo_indexable(translated_key, geo)
  end

  # Promotes only the **indexable** companion for a %Geo.*{} — used when
  # a Geo struct is nested inside a non-Geo attribute (TypedStruct,
  # embedded resource, etc.). The canonical GeoJSON for the nested geo
  # lives inside the parent's JSON blob (via Util.to_json_safe's geo
  # handling), so we only need the indexable sidecar at the node level.
  defp promote_geo_indexable(acc, translated_key, %Geo.Point{coordinates: {x, y}}) do
    Map.put(acc, "#{translated_key}.point", Bolty.Types.Point.create(:wgs_84, x, y))
  end

  defp promote_geo_indexable(acc, translated_key, %_{} = geo) do
    if AshGeo.is_geo(geo.__struct__) do
      [west, south, east, north] = AshNeo4j.GeoJson.bbox(geo)

      acc
      |> Map.put("#{translated_key}.bbSW", Bolty.Types.Point.create(:wgs_84, west, south))
      |> Map.put("#{translated_key}.bbNE", Bolty.Types.Point.create(:wgs_84, east, north))
    else
      acc
    end
  end

  # Recursively walks a value (typically the input form of a non-Geo
  # attribute — struct, map, etc.) looking for nested %Geo.*{} structs.
  # Returns a list of `{path :: [String.t()], geo :: %Geo.*{}}` pairs.
  # Path is the dotted hierarchy down to each Geo leaf, with the
  # outer-most attribute name supplied by the caller as the initial
  # path element.
  #
  # Arrays are skipped for now — union-bbox-over-array-elements is a
  # follow-up design question. The pattern extends cleanly when wanted.
  defp geo_walk(value, path)

  defp geo_walk(%struct{} = value, path) do
    if AshGeo.is_geo(struct) do
      [{path, value}]
    else
      value
      |> Map.from_struct()
      |> Enum.flat_map(fn {k, v} -> geo_walk(v, path ++ [to_string(k)]) end)
    end
  end

  defp geo_walk(map, path) when is_map(map) do
    Enum.flat_map(map, fn {k, v} -> geo_walk(v, path ++ [to_string(k)]) end)
  end

  defp geo_walk(_other, _path), do: []

  defp apply_aggregates_to_records(records, [], _resource), do: {:ok, records}

  defp apply_aggregates_to_records(records, aggregates, resource) do
    mapping = ResourceInfo.mapping(resource)
    pk_field = hd(Ash.Resource.Info.primary_key(resource))
    neo4j_pk = Keyword.get(mapping.properties, pk_field, pk_field)
    ids = Enum.map(records, &Map.get(&1, pk_field))

    Enum.reduce_while(aggregates, {:ok, records}, fn aggregate, {:ok, acc_records} ->
      case run_aggregate_for_ids(mapping, neo4j_pk, ids, aggregate, :per_record) do
        {:ok, agg_map} ->
          updated =
            Enum.map(acc_records, fn record ->
              id = Map.get(record, pk_field)
              value = Map.get(agg_map, id, aggregate.default_value)
              Map.put(record, aggregate.name, value)
            end)

          {:cont, {:ok, updated}}

        {:error, e} ->
          {:halt, {:error, e}}
      end
    end)
  end

  defp apply_calculations_to_records(records, [], _resource), do: {:ok, records}

  defp apply_calculations_to_records(records, calculations, resource) do
    Enum.reduce_while(calculations, {:ok, records}, fn {calculation, expression}, {:ok, acc} ->
      case Ash.Filter.hydrate_refs(expression, %{resource: resource, public?: false, eval?: true}) do
        {:ok, hydrated} ->
          updated =
            Enum.map(acc, fn record ->
              case Ash.Expr.eval_hydrated(hydrated, record: record, resource: resource, unknown_on_unknown_refs?: true) do
                {:ok, value} -> Map.put(record, calculation.name, value)
                _ -> record
              end
            end)

          {:cont, {:ok, updated}}

        {:error, e} ->
          {:halt, {:error, e}}
      end
    end)
  end

  defp apply_calculation_sort(records, sort, _domain) when sort in [nil, []], do: records

  defp apply_calculation_sort(records, sort, domain) do
    if Enum.any?(sort, fn {term, _} -> is_struct(term, Ash.Query.Calculation) end) do
      Ash.Actions.Sort.runtime_sort(records, sort, domain: domain, rekey?: false)
    else
      records
    end
  end

  defp run_aggregate_for_ids(_mapping, _neo4j_pk, [], aggregate, _mode) do
    {:ok, aggregate.default_value}
  end

  defp run_aggregate_for_ids(%ResourceMapping{} = mapping, neo4j_pk, ids, aggregate, mode) do
    case resolve_aggregate_path(mapping, aggregate.relationship_path) do
      {:ok, path_segments, dest_mapping} ->
        neo4j_field =
          if aggregate.field && is_atom(aggregate.field),
            do: Keyword.get(dest_mapping.properties, aggregate.field, aggregate.field),
            else: nil

        embedded = embedded_field_type(dest_mapping.module, aggregate.field)

        cond do
          # Expression-based aggregates always load full records in Elixir;
          # run_expr_agg handles aggregate.filter internally via apply_record_filter.
          is_struct(aggregate.field, Ash.Query.Calculation) ->
            run_expr_agg(mapping, neo4j_pk, ids, aggregate, mode, path_segments, dest_mapping)

          # When a filter is present, try to push scalar == conditions into Cypher.
          # Falls back to Elixir-side filtering for complex or embedded-field filters.
          aggregate_has_filter?(aggregate) ->
            case {simple_agg_filter(aggregate, dest_mapping), embedded} do
              {{:ok, dest_conditions}, nil} ->
                run_simple_filtered_aggregate(
                  mapping,
                  neo4j_pk,
                  ids,
                  aggregate,
                  mode,
                  path_segments,
                  neo4j_field,
                  dest_conditions
                )

              _ ->
                run_filtered_aggregate(mapping, neo4j_pk, ids, aggregate, mode, path_segments, dest_mapping)
            end

          embedded ->
            {field_type, field_constraints} = embedded

            run_embedded_agg(
              mapping,
              neo4j_pk,
              ids,
              aggregate,
              mode,
              path_segments,
              neo4j_field,
              field_type,
              field_constraints
            )

          true ->
            query =
              case mode do
                :per_record ->
                  CypherQuery.aggregate_per_record(
                    mapping.label_pair,
                    neo4j_pk,
                    ids,
                    path_segments,
                    aggregate.kind,
                    neo4j_field,
                    aggregate.name,
                    aggregate.uniq?
                  )

                :total ->
                  CypherQuery.aggregate_total(
                    mapping.label_pair,
                    neo4j_pk,
                    ids,
                    path_segments,
                    aggregate.kind,
                    neo4j_field,
                    aggregate.name,
                    aggregate.uniq?
                  )
              end

            case Cypher.run(query) do
              {:ok, %Bolty.Response{results: rows}} ->
                case mode do
                  :per_record ->
                    {:ok,
                     Map.new(rows, fn row ->
                       {Map.get(row, "source_id"), Map.get(row, to_string(aggregate.name))}
                     end)}

                  :total ->
                    value = rows |> List.first(%{}) |> Map.get(to_string(aggregate.name), aggregate.default_value)
                    {:ok, value}
                end

              {:error, e} ->
                {:error, e}
            end
        end

      {:error, e} ->
        {:error, e}
    end
  end

  # Handles any aggregate that carries a filter expression. Loads all destination
  # records for the given source IDs via Elixir, applies the Ash runtime filter,
  # then computes the aggregate in Elixir.
  #
  # This path is also used for expression-based aggregates (Ash.Query.Calculation
  # field) when a filter is present, because we already load full records there.
  defp run_filtered_aggregate(mapping, neo4j_pk, ids, aggregate, mode, path_segments, dest_mapping) do
    query = CypherQuery.related_nodes(mapping.label_pair, neo4j_pk, ids, path_segments)
    dest_resource = dest_mapping.module
    domain = Ash.Resource.Info.domain(dest_resource)

    with {:ok, %Bolty.Response{results: rows}} <- Cypher.run(query) do
      pairs =
        Enum.flat_map(rows, fn row ->
          source_id = Map.get(row, "source_id")
          dest_node = Map.get(row, "dest_node")

          if dest_node do
            case convert_node_to_resource(dest_resource, dest_node) do
              {:ok, record} -> [{source_id, record}]
              _ -> []
            end
          else
            []
          end
        end)

      case mode do
        :per_record ->
          grouped = Enum.group_by(pairs, &elem(&1, 0), &elem(&1, 1))

          result =
            Map.new(grouped, fn {source_id, records} ->
              {:ok, filtered} = Ash.Filter.Runtime.filter_matches(domain, records, aggregate.query.filter)
              values = extract_aggregate_field_values(filtered, aggregate)
              {source_id, apply_elixir_aggregate(aggregate.kind, values, aggregate.default_value)}
            end)

          {:ok, result}

        :total ->
          all_records = Enum.map(pairs, &elem(&1, 1))
          {:ok, filtered} = Ash.Filter.Runtime.filter_matches(domain, all_records, aggregate.query.filter)
          values = extract_aggregate_field_values(filtered, aggregate)
          {:ok, apply_elixir_aggregate(aggregate.kind, values, aggregate.default_value)}
      end
    end
  end

  # Handles aggregates whose filter is a set of simple scalar == conditions that can be
  # expressed as WHERE clauses in Cypher, avoiding full record loading in Elixir.
  defp run_simple_filtered_aggregate(mapping, neo4j_pk, ids, aggregate, mode, path_segments, neo4j_field, dest_conditions) do
    query =
      case mode do
        :per_record ->
          CypherQuery.aggregate_per_record(
            mapping.label_pair,
            neo4j_pk,
            ids,
            path_segments,
            aggregate.kind,
            neo4j_field,
            aggregate.name,
            aggregate.uniq?,
            dest_conditions
          )

        :total ->
          CypherQuery.aggregate_total(
            mapping.label_pair,
            neo4j_pk,
            ids,
            path_segments,
            aggregate.kind,
            neo4j_field,
            aggregate.name,
            aggregate.uniq?,
            dest_conditions
          )
      end

    case Cypher.run(query) do
      {:ok, %Bolty.Response{results: rows}} ->
        case mode do
          :per_record ->
            {:ok,
             Map.new(rows, fn row ->
               {Map.get(row, "source_id"), Map.get(row, to_string(aggregate.name))}
             end)}

          :total ->
            value = rows |> List.first(%{}) |> Map.get(to_string(aggregate.name), aggregate.default_value)
            {:ok, value}
        end

      {:error, e} ->
        {:error, e}
    end
  end

  # Returns {:ok, [{prop_string, value}]} when the aggregate filter consists entirely of
  # scalar == equality predicates on non-embedded destination attributes, enabling
  # WHERE pushdown into Cypher. Returns :complex otherwise and falls back to Elixir-side filtering.
  defp simple_agg_filter(aggregate, dest_mapping) do
    filter = aggregate_query_filter(aggregate)

    try do
      simple = Ash.Filter.to_simple_filter(filter, skip_invalid?: false)
      predicates = Map.get(simple, :predicates, [])

      if Enum.empty?(predicates) do
        :complex
      else
        Enum.reduce_while(predicates, {:ok, []}, fn predicate, {:ok, acc} ->
          cond do
            Map.get(predicate, :operator) != :== ->
              {:halt, :complex}

            not match?(%Ash.Query.Ref{}, Map.get(predicate, :left)) ->
              {:halt, :complex}

            match?(%Ash.Query.Calculation{}, Map.get(predicate.left, :attribute)) ->
              {:halt, :complex}

            true ->
              attr_name = Ash.Query.Ref.name(predicate.left)

              case embedded_field_type(dest_mapping.module, attr_name) do
                nil ->
                  prop = Keyword.get(dest_mapping.properties, attr_name, attr_name) |> to_string()
                  {:cont, {:ok, acc ++ [{prop, predicate.right}]}}

                _ ->
                  {:halt, :complex}
              end
          end
        end)
      end
    rescue
      _ -> :complex
    end
  end

  # Extracts the aggregate's target field value from each record, respecting uniq?.
  defp extract_aggregate_field_values(records, aggregate) do
    values =
      Enum.map(records, fn record ->
        case aggregate.field do
          nil -> record
          field when is_atom(field) -> Map.get(record, field)
          _ -> record
        end
      end)

    if aggregate.uniq?, do: Enum.uniq(values), else: values
  end

  defp embedded_field_type(resource_module, field_name) when is_atom(field_name) do
    case Ash.Resource.Info.attribute(resource_module, field_name) do
      nil ->
        nil

      attr ->
        type = Ash.Type.get_type(attr.type)

        case TypeClassifier.classify(type) do
          {:ok, :ash_json, _} -> {type, attr.constraints}
          _ -> nil
        end
    end
  end

  defp embedded_field_type(_, _), do: nil

  defp run_embedded_agg(
         mapping,
         neo4j_pk,
         ids,
         aggregate,
         mode,
         path_segments,
         neo4j_field,
         field_type,
         field_constraints
       ) do
    query =
      case mode do
        :per_record ->
          CypherQuery.aggregate_per_record(
            mapping.label_pair,
            neo4j_pk,
            ids,
            path_segments,
            :list,
            neo4j_field,
            aggregate.name,
            aggregate.uniq?
          )

        :total ->
          CypherQuery.aggregate_total(
            mapping.label_pair,
            neo4j_pk,
            ids,
            path_segments,
            :list,
            neo4j_field,
            aggregate.name,
            aggregate.uniq?
          )
      end

    case Cypher.run(query) do
      {:ok, %Bolty.Response{results: rows}} ->
        agg_key = to_string(aggregate.name)

        case mode do
          :per_record ->
            {:ok,
             Map.new(rows, fn row ->
               source_id = Map.get(row, "source_id")
               raw_list = Map.get(row, agg_key, [])
               cast_list = cast_raw_list(raw_list, field_type, field_constraints)
               {source_id, apply_elixir_aggregate(aggregate.kind, cast_list, aggregate.default_value)}
             end)}

          :total ->
            raw_list = rows |> List.first(%{}) |> Map.get(agg_key, [])
            cast_list = cast_raw_list(raw_list, field_type, field_constraints)
            {:ok, apply_elixir_aggregate(aggregate.kind, cast_list, aggregate.default_value)}
        end

      {:error, e} ->
        {:error, e}
    end
  end

  defp run_expr_agg(mapping, neo4j_pk, ids, aggregate, mode, path_segments, dest_mapping) do
    query = CypherQuery.related_nodes(mapping.label_pair, neo4j_pk, ids, path_segments)
    dest_resource = dest_mapping.module
    domain = Ash.Resource.Info.domain(dest_resource)
    calc = aggregate.field
    expr = calc.opts[:expr]

    case Ash.Filter.hydrate_refs(expr, %{resource: dest_resource, public?: false, eval?: true}) do
      {:ok, hydrated} ->
        case Cypher.run(query) do
          {:ok, %Bolty.Response{results: rows}} ->
            record_pairs =
              Enum.flat_map(rows, fn row ->
                source_id = Map.get(row, "source_id")
                dest_node = Map.get(row, "dest_node")

                if dest_node do
                  case convert_node_to_resource(dest_resource, dest_node) do
                    {:ok, record} -> [{source_id, record}]
                    _ -> []
                  end
                else
                  []
                end
              end)

            # Apply aggregate filter if present, then evaluate the expression.
            pairs =
              apply_record_filter(record_pairs, aggregate_query_filter(aggregate), domain)
              |> Enum.flat_map(fn {source_id, record} ->
                case Ash.Expr.eval_hydrated(hydrated,
                       record: record,
                       resource: dest_resource,
                       unknown_on_unknown_refs?: true
                     ) do
                  {:ok, value} when not is_nil(value) -> [{source_id, value}]
                  _ -> []
                end
              end)

            case mode do
              :per_record ->
                grouped = Enum.group_by(pairs, &elem(&1, 0), &elem(&1, 1))

                {:ok,
                 Map.new(grouped, fn {source_id, values} ->
                   {source_id, apply_elixir_aggregate(aggregate.kind, values, aggregate.default_value)}
                 end)}

              :total ->
                values = Enum.map(pairs, &elem(&1, 1))
                {:ok, apply_elixir_aggregate(aggregate.kind, values, aggregate.default_value)}
            end

          {:error, e} ->
            {:error, e}
        end

      {:error, e} ->
        {:error, e}
    end
  end

  # Returns true when the aggregate carries a real (non-trivial) filter in its
  # query. Ash always provides an Ash.Query on the aggregate; unfiltered aggregates
  # have %Ash.Filter{expression: true}. We only route through the Elixir-side
  # path when there is an actual user-defined filter to honour.
  defp aggregate_has_filter?(aggregate) do
    case aggregate_query_filter(aggregate) do
      %Ash.Filter{expression: true} -> false
      %Ash.Filter{} -> true
      _ -> false
    end
  end

  # Extracts the filter from aggregate.query, returning nil if absent.
  defp aggregate_query_filter(aggregate) do
    case Map.get(aggregate, :query) do
      %Ash.Query{filter: filter} -> filter
      _ -> nil
    end
  end

  # Applies an Ash filter (if any) to a list of {source_id, record} pairs,
  # keeping per-source grouping so filter predicates referencing destination
  # attributes are evaluated correctly.
  defp apply_record_filter(pairs, nil, _domain), do: pairs

  defp apply_record_filter(pairs, filter, domain) do
    grouped = Enum.group_by(pairs, &elem(&1, 0), &elem(&1, 1))

    Enum.flat_map(grouped, fn {source_id, records} ->
      {:ok, filtered} = Ash.Filter.Runtime.filter_matches(domain, records, filter)
      Enum.map(filtered, &{source_id, &1})
    end)
  end

  defp cast_raw_list(raw_list, field_type, field_constraints) when is_list(raw_list) do
    case Cast.cast({:array, field_type}, raw_list, field_constraints) do
      {:ok, values} -> values
      {:error, _} -> []
    end
  end

  defp cast_raw_list(_, _, _), do: []

  defp apply_elixir_aggregate(:list, values, _default), do: values
  defp apply_elixir_aggregate(:first, values, default), do: List.first(values, default)
  defp apply_elixir_aggregate(:count, values, _default), do: length(values)
  defp apply_elixir_aggregate(:exists, values, _default), do: values != []
  defp apply_elixir_aggregate(:sum, [], default), do: default
  defp apply_elixir_aggregate(:sum, values, _default), do: Enum.sum(values)
  defp apply_elixir_aggregate(:avg, [], default), do: default
  defp apply_elixir_aggregate(:avg, values, _default), do: Enum.sum(values) / length(values)
  defp apply_elixir_aggregate(:min, [], default), do: default
  defp apply_elixir_aggregate(:min, values, _default), do: Enum.min(values)
  defp apply_elixir_aggregate(:max, [], default), do: default
  defp apply_elixir_aggregate(:max, values, _default), do: Enum.max(values)

  defp resolve_aggregate_path(%ResourceMapping{} = mapping, relationship_path) do
    Enum.reduce_while(relationship_path, {mapping, []}, fn name, {current_mapping, segments} ->
      case Enum.find(current_mapping.edges, &(&1.relationship == name)) do
        nil ->
          {:halt, {:error, "relationship #{name} not found on #{current_mapping.module}"}}

        %EdgeDescriptor{label: edge_label, direction: direction, destination_label: dest_label} ->
          relationship = Ash.Resource.Info.relationship(current_mapping.module, name)
          next_mapping = ResourceInfo.mapping(relationship.destination)
          {:cont, {next_mapping, [{edge_label, direction, dest_label} | segments]}}
      end
    end)
    |> case do
      {:error, _} = error -> error
      {dest_mapping, segments} -> {:ok, Enum.reverse(segments), dest_mapping}
    end
  end
end
