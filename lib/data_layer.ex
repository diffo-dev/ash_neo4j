# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.DataLayer do
  @moduledoc "Ash DataLayer for Neo4j"

  @behaviour Ash.DataLayer

  require Logger
  alias AshNeo4j.DataLayer.Info
  alias AshNeo4j.QueryHelper
  alias AshNeo4j.Neo4jHelper
  alias AshNeo4j.DataLayer.Cast
  alias AshNeo4j.DataLayer.Dump

  @filter_stream_size 100

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
  # def can?(_, :bulk_create), do: true
  def can?(_, :offset), do: true
  def can?(_, :boolean_filter), do: true
  # def can?(_, :transact), do: true
  def can?(_, {:filter_expr, _}), do: true
  def can?(_, :nested_expressions), do: true
  # def can?(_, :expression_calculation), do: true
  # def can?(_, :expression_calculation_sort), do: true
  def can?(_, {:sort, _}), do: true
  def can?(_, {:join, _}), do: true
  def can?(_, {:lateral_join, _}), do: true
  def can?(_, {:filter_relationship, _}), do: true
  def can?(_, _), do: false

  @neo4j %Spark.Dsl.Section{
    name: :neo4j,
    examples: [
      """
      neo4j do
        label :Comment
        relate [{:post, :BELONGS_TO, :outgoing}]
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
        required: false
      ],
      guard: [
        type: {:list, {:tuple, [:atom, :atom, :atom]}},
        doc: "Optional list of node relationships, as tuples of {edge_label, edge_direction, destination_label}",
        required: false
      ],
      skip: [
        type: {:list, :atom},
        doc: "Optional list of attributes not to be stored directly as node properties",
        required: false
      ]
    ]
  }

  @impl true
  def limit(query, offset, _), do: {:ok, %{query | limit: offset}}

  @impl true
  def offset(query, offset, _), do: {:ok, %{query | offset: offset}}

  @impl true
  def filter(query, filter, _resource) do
    # TODO check filter involves node properties
    {:ok, %{query | filter: filter}}
  end

  @impl true
  def sort(query, sort, _resource) do
    # TODO check sort involves node properties
    {:ok, %{query | sort: sort}}
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
    verifiers: [
      AshNeo4j.Verifiers.VerifyLabelPascalCase,
      AshNeo4j.Verifiers.VerifyRelate,
      AshNeo4j.Verifiers.VerifyGuard,
      AshNeo4j.Verifiers.VerifyPropertiesCamelCase,
      AshNeo4j.Verifiers.VerifyEnrichable
    ],
    transformers: [
      AshNeo4j.Transformers.TransformEnsureLabelled,
      AshNeo4j.Transformers.TransformAddDomainLabel,
      AshNeo4j.Transformers.TransformEnsureIdTranslated,
      AshNeo4j.Transformers.TransformDefaultRelate,
      AshNeo4j.Transformers.TransformAddTranslations,
      AshNeo4j.Transformers.TransformAddRelationshipAttributes
    ]

  defmodule Query do
    @moduledoc false
    defstruct [:resource, :sort, :filter, :limit, :offset, :domain]
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
          results =
            convert_groups_to_resources(query, groups)
            |> filter_stream(query.domain, query.filter)
            |> Enum.to_list()

          {:ok, results}
      end

    Logger.debug("""
    AshNeo4j.DataLayer: run_query result #{inspect(result)}
    """)

    result
  end

  @impl true
  @spec create(atom() | map(), any()) ::
          {:error, <<_::64, _::_*8>> | %{:__exception__ => true, :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, any()}
  def create(resource, changeset) do
    Logger.debug("""
    AshNeo4j.DataLayer: create(#{inspect(resource)}, #{inspect(changeset)})
    """)

    primary_keys = Ash.Resource.Info.primary_key(resource)
    id_attributes = Map.take(changeset.attributes, primary_keys)

    result =
      if Enum.empty?(id_attributes) do
        {:error, "no values supplied for primary keys #{primary_keys}"}
      else
        create_from_attributes(resource, changeset.attributes)
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

    id_properties = id_properties(resource, changeset.attributes)

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

    subject_id = id_properties(resource, changeset.data)
    subject_label = Info.label(resource)

    update_properties = dump_properties(resource, changeset.attributes)

    remove_property_names = remove_property_names(resource, changeset.attributes)

    property_update_result =
      if !Enum.empty?(update_properties) or !Enum.empty?(remove_property_names) do
        # update properties
        case subject_label |> Neo4jHelper.update_node(subject_id, update_properties, remove_property_names) do
          {:ok, %Bolty.Response{results: []}} ->
            {:error, "no result to update node"}

          {:ok, %Bolty.Response{results: [node_map | _]}} ->
            node = Map.get(node_map, "n")
            {:ok, convert_node_to_resource(resource, node)}

          {:error, error} ->
            {:error, error}
        end
      end

    relationship_update_result =
      if accessing_from = Map.get(changeset.context, :accessing_from) do
        object_resource = Map.get(accessing_from, :source)
        object_label = Info.label(object_resource)
        object_relationship_name = Map.get(accessing_from, :name)
        object_node_relationship = Info.node_relationship(object_resource, object_relationship_name)

        if Map.get(accessing_from, :unrelating?) do
          # unrelate
          # example changeset.context: %{changed?: true, accessing_from: %{name: :events, source: AshNeo4j.Test.Resource.Service}}
          # example changeset.attributes %{post_id: nil}
          # note changeset.data has the current post_id
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
                     Info.reverse(object_to_subject_direction)
                   ) do
                {:ok, %Bolty.Response{results: []}} ->
                  {:error, "no result to unrelate nodes"}

                {:ok, %Bolty.Response{results: [node_map | _]}} ->
                  node = Map.get(node_map, "s")
                  {:ok, convert_node_to_resource(resource, node)}

                {:error, error} ->
                  {:error, error}
              end
          end
        else
          # relate
          # example changeset.context: %{changed?: true, accessing_from: %{name: :events, source: AshNeo4j.Test.Resource.Service}}
          # TODO the relationship may be exclusive, so we may need to delete other source or destination relationships
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
                     Info.reverse(object_to_subject_direction)
                   ) do
                {:ok, %Bolty.Response{results: []}} ->
                  {:error, "no result to relate nodes"}

                {:ok, %Bolty.Response{results: [node_map | _]}} ->
                  node = Map.get(node_map, "s")
                  {:ok, convert_node_to_resource(resource, node)}

                {:error, error} ->
                  {:error, error}
              end
          end
        end
      else
        if changeset.relationships do
          Enum.reduce_while(changeset.relationships, nil, fn {relationship_name, relationship_change}, _acc ->
            subject_node_relationship =
              Info.node_relationship(resource, relationship_name)

            subject_relationship =
              Ash.Resource.Info.relationship(resource, relationship_name)

            object_resource = subject_relationship.destination
            object_label = Info.label(object_resource)

            {arguments, options} = hd(relationship_change)
            type = Keyword.get(options, :type)

            cond do
              arguments == [] or type == :remove ->
                # unrelate
                subject_source_attribute = subject_relationship.source_attribute
                subject_destination_attribute = subject_relationship.destination_attribute
                object_property_name = Info.convert_to_property_name(object_resource, subject_destination_attribute)
                object_property_value = Map.get(changeset.data, subject_source_attribute)
                object_id = %{object_property_name => object_property_value}

                case map_size(object_id) do
                  0 ->
                    {:error, "couldn't unrelate nodes"}

                  _ ->
                    {_relationship_name, edge_label, subject_to_object_direction, _destination_label} =
                      subject_node_relationship

                    case Neo4jHelper.unrelate_nodes(
                           subject_label,
                           subject_id,
                           object_label,
                           object_id,
                           edge_label,
                           subject_to_object_direction
                         ) do
                      {:ok, %Bolty.Response{results: []}} ->
                        {:halt, {:error, "no result to unrelate nodes"}}

                      {:ok, %Bolty.Response{results: [node_map | _]}} ->
                        node = Map.get(node_map, "s")
                        {:cont, {:ok, convert_node_to_resource(resource, node)}}

                      {:error, error} ->
                        {:halt, {:error, error}}
                    end
                end

              true ->
                # relate each argument
                arg_relate_result =
                  Enum.reduce_while(arguments, nil, fn argument, _acc ->
                    object_id = Info.convert_to_properties(object_resource, argument)

                    case map_size(object_id) do
                      0 ->
                        {:halt, {:error, "couldn't relate nodes using argument"}}

                      _ ->
                        {_relationship_name, edge_label, subject_to_object_direction, _destination_label} =
                          subject_node_relationship

                        subject_exclusive? = Info.source_exclusive?(resource, relationship_name)
                        object_exclusive? = Info.destination_exclusive?(resource, relationship_name)

                        case Neo4jHelper.relate_nodes(
                               subject_label,
                               subject_id,
                               object_label,
                               object_id,
                               edge_label,
                               subject_to_object_direction,
                               {subject_exclusive?, object_exclusive?}
                             ) do
                          {:ok, %Bolty.Response{results: []}} ->
                            {:halt, {:error, "no result to relate nodes"}}

                          {:ok, %Bolty.Response{results: [node_map | _]}} ->
                            node = Map.get(node_map, "s")
                            {:cont, {:ok, convert_node_to_resource(resource, node)}}

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

    label = Info.label(resource)
    id_properties = id_properties(resource, changeset.data)

    result =
      case Neo4jHelper.safe_delete_nodes(label, id_properties, Info.preserve_node_relationships(resource)) do
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
  def transaction(resource, fun, _timeout, _) do
    label = Info.label(resource)

    :global.trans(
      {{:neo4j, label}, System.unique_integer()},
      fn ->
        try do
          Process.put({:neo4j_in_transaction, label}, true)
          {:res, fun.()}
        catch
          {{:neo4j_rollback, ^label}, value} ->
            {:error, value}
        end
      end,
      [node() | :erlang.nodes()],
      0
    )
    |> case do
      {:res, result} -> {:ok, result}
      {:error, error} -> {:error, error}
      :aborted -> {:error, "transaction failed"}
    end
  end

  @impl true
  def rollback(resource, error) do
    throw({{:neo4j_rollback, Info.label(resource)}, error})
  end

  @impl true
  def in_transaction?(resource) do
    Process.get({:neo4j_in_transaction, Info.label(resource)}, false) == true
  end

  defp filter_matches(records, nil, _domain), do: records

  defp filter_matches(records, filter, domain) do
    {:ok, records} = Ash.Filter.Runtime.filter_matches(domain, records, filter)
    records
  end

  # consolidates list of groups in row form [ %{s, r, d} ] to values in form [{s, [{r, d}]}]
  # also handles [%{s, r1, d1, r0, d0}] to values in form [{s, [{r1, d1}, {r0, d0}}]
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
          # new source node
          [{s, tuples}]

        [previous | tail] = acc ->
          cond do
            Map.get(s, :id) == elem(previous, 0).id ->
              # same node
              cond do
                tuples == [] ->
                  # same node with no relationship
                  acc

                true ->
                  # same node with new relationship
                  [{s, tuples ++ elem(previous, 1)} | tail]
              end

            true ->
              # new node
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

  # converts nodes to resources, where the input is a list of related node groups
  # the output of each group is a single resource, enriched with attributes linking related nodes
  defp convert_groups_to_resources(query, groups) when is_struct(query, Query) and is_list(groups) do
    consolidate_groups(groups)
    |> Stream.map(&convert_to_resource(query, &1))
  end

  defp convert_to_resource(query, consolidated_group)
       when is_struct(query, Query) and is_tuple(consolidated_group) do
    source_node = elem(consolidated_group, 0)
    related = elem(consolidated_group, 1)

    enrichments =
      Enum.reduce(related, [], &enrichments(query.resource, &2, &1))
      |> consolidate_enrichments()

    convert_node_to_resource(query.resource, source_node, enrichments)
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
                  # merge name list values
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

  defp enrichments(resource, acc, {edge, dest_node})
       when is_atom(resource) and is_list(acc) and is_map(edge) and is_map(dest_node) do
    dest_labels = Enum.into(dest_node.labels, [], &String.to_atom(&1))
    edge_label = String.to_atom(edge.type)
    edge_direction = edge_direction(edge, dest_node)

    relationship =
      Info.relationship(resource, edge_label, edge_direction, dest_labels)

    if relationship != nil do
      reverse_node_relationship = Info.reverse_node_relationship(resource, relationship.name)

      reverse_relationship =
        cond do
          reverse_node_relationship == nil ->
            nil

          true ->
            Ash.Resource.Info.relationship(relationship.destination, elem(reverse_node_relationship, 0))
        end

      cond do
        relationship.cardinality == :one && relationship.type == :belongs_to ->
          destination_property =
            Info.convert_to_property_name(relationship.destination, relationship.destination_attribute)

          [
            {relationship.source_attribute, Map.get(dest_node.properties, destination_property)} | acc
          ]

        reverse_relationship != nil &&
            (reverse_relationship.cardinality == :one && reverse_relationship.type == :has_one) ->
          source_property =
            Info.convert_to_property_name(relationship.source, relationship.source_attribute)

          [
            {relationship.destination_attribute, Map.get(dest_node.properties, source_property)} | acc
          ]

        # 'back to back' has_many implementing many_to_many
        relationship.cardinality == :many && reverse_relationship != nil && reverse_relationship.cardinality == :many ->
          dest_resource = convert_node_to_resource(relationship.destination, dest_node, [])
          [{relationship.name, [dest_resource]} | acc]

        true ->
          Logger.warning(
            "AshNeo4j.DataLayer: unable to enrich source node #{inspect(Info.label(resource))} with edge #{inspect(edge.type)} and destination node #{inspect(dest_node.labels)}, unsupported"
          )

          acc
      end
    else
      Logger.warning(
        "AshNeo4j.DataLayer: unable to enrich source node #{inspect(Info.label(resource))} with edge #{inspect(edge.type)} and destination node #{inspect(dest_node.labels)}, no relationship"
      )

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

  defp convert_node_to_resource(resource, node, enrichments \\ [])
       when is_atom(resource) and is_map(node) and is_list(enrichments) do
    enriched =
      Enum.into(enrichments, %{}, fn {field, value} ->
        {field, value}
      end)

    fields =
      Enum.into(Info.translations(resource), enriched, fn {resource_field, node_field} ->
        property_value = Map.get(node.properties, to_string(node_field))
        {resource_field, cast_attribute(resource, resource_field, property_value)}
      end)

    # nil belongs_to if destination_attribute is nil
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

    struct!(resource, nilled_fields)
    |> Ash.Resource.set_metadata(%{node_id: node.id, data_layer: __MODULE__, labels: node.labels})
    |> Ash.Resource.set_meta(struct(Ecto.Schema.Metadata, state: :loaded))
  end

  defp filter_stream(stream, _domain, nil), do: stream

  defp filter_stream(stream, domain, filter) do
    stream
    |> Stream.chunk_every(@filter_stream_size)
    |> Stream.flat_map(fn chunk ->
      filter_matches(chunk, filter, domain)
    end)
  end

  defp create_from_attributes(resource, attributes) when is_atom(resource) and is_map(attributes) do
    properties = dump_properties(resource, attributes)

    case create_node(resource, properties) do
      {:ok, source_resource} ->
        relate_nodes(source_resource, resource, attributes)

      {:error, error} ->
        {:error, error}
    end
  end

  defp relate_nodes(source_resource, resource, attributes)
       when is_struct(source_resource) and is_atom(resource) and is_map(attributes) do
    relationship_attributes = Info.relationship_attributes(resource) |> Keyword.delete(:id)
    relationship_source_attributes = Map.take(attributes, Keyword.keys(relationship_attributes))

    case Enum.count(relationship_source_attributes) do
      0 ->
        {:ok, source_resource}

      _ ->
        # accumulate relationships
        relationships =
          relationship_attributes
          |> Enum.reduce(
            [],
            fn {source_attribute, name}, acc ->
              relationship = Ash.Resource.Info.relationship(resource, name)
              dest_resource = relationship.destination
              node_relationship = Info.node_relationship(resource, name)

              case node_relationship do
                {^name, edge_label, edge_direction, destination_label} ->
                  dest_node_property_name =
                    Keyword.get(Info.translations(dest_resource), relationship.destination_attribute)

                  dest_id_value = Map.get(relationship_source_attributes, source_attribute)

                  if dest_id_value == nil do
                    acc
                  else
                    dest_id = %{dest_node_property_name => dest_id_value}
                    exclusive = Info.destination_exclusive?(resource, name)
                    [{destination_label, dest_id, edge_label, edge_direction, exclusive} | acc]
                  end

                nil ->
                  acc
              end
            end
          )

        # relate resources, potentially unrelating destination resources
        label = Info.label(resource)
        id_properties = id_properties(resource, attributes)

        case Neo4jHelper.relate_nodes(label, id_properties, relationships) do
          :ok ->
            case Neo4jHelper.read_nodes_related(label, id_properties) do
              {:ok, %Bolty.Response{results: groups}} ->
                consolidated_groups = consolidate_groups(groups)
                # return the enriched created resource
                cond do
                  length(consolidated_groups) == 1 ->
                    query = resource_to_query(resource, Ash.Resource.Info.domain(resource))
                    source_resource = convert_to_resource(query, hd(consolidated_groups))
                    {:ok, source_resource}

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

  defp create_node(resource, properties) when is_atom(resource) and is_map(properties) do
    case Info.labels(resource) |> Neo4jHelper.create_node(properties) do
      {:ok, %Bolty.Response{results: [node_map | _]}} ->
        node = Map.get(node_map, "n")
        {:ok, convert_node_to_resource(resource, node)}

      {:error, error} ->
        {:error, error}
    end
  end

  defp id_properties(resource, map) when is_atom(resource) and is_map(map) do
    primary_keys = Ash.Resource.Info.primary_key(resource)
    translations = Info.translations(resource)
    Enum.into(primary_keys, %{}, fn key -> {Keyword.get(translations, key, key), Map.get(map, key)} end)
  end

  defp relationship_properties(source_resource, dest_resource, source_map, dest_relationship_name)
       when is_atom(source_resource) and is_atom(dest_resource) and is_map(source_map) and
              is_atom(dest_relationship_name) do
    # source_relationship_name
    source_node_relationship = Info.reverse_node_relationship(dest_resource, dest_relationship_name)

    if source_node_relationship != nil do
      source_relationship_name = elem(source_node_relationship, 0)
      source_relationship = Ash.Resource.Info.relationship(source_resource, source_relationship_name)
      value = Map.get(source_map, source_relationship.source_attribute)

      if value != nil do
        dest_property_name =
          Info.convert_to_property_name(dest_resource, source_relationship.destination_attribute)
          |> String.to_atom()

        %{dest_property_name => value}
      else
        %{}
      end
    else
      %{}
    end
  end

  # defp properties(resource, map) when is_atom(resource) and is_map(map) do
  #  Info.translations(resource)
  #  |> Enum.into(%{}, fn {key, translated_key} -> {translated_key, Map.get(map, key)} end)
  #  |> Map.reject(fn {_k, v} -> v == nil end)
  # end

  defp remove_property_names(resource, map) when is_atom(resource) and is_map(map) do
    map
    |> Map.reject(fn {_k, v} -> v != nil end)
    |> Enum.into([], fn {field, _} -> Keyword.get(Info.translations(resource), field, nil) end)
    |> Enum.reject(fn field -> field == nil end)
  end

  def cast_attribute(_resource, _name, nil) do
    nil
  end

  def cast_attribute(resource, name, value) when is_atom(resource) and is_atom(name) do
    attribute = Ash.Resource.Info.attribute(resource, name)

    if attribute == nil do
      Logger.warning(
        "AshNeo4j.DataLayer: no attribute found for resource #{inspect(resource)} and name #{inspect(name)}, returning original value"
      )

      value
    else
      Cast.cast(attribute.type, value, attribute.constraints)
    end
  end

  defp dump_properties(resource, attributes) when is_atom(resource) and is_map(attributes) do
    Info.translations(resource)
    |> Enum.reduce(%{}, fn {key, translated_key}, acc ->
      value = Map.get(attributes, key)

      if value != nil do
        attribute = Ash.Resource.Info.attribute(resource, key)

        attribute_type =
          Ash.Type.get_type!(attribute.type)

        Map.put(acc, translated_key, Dump.dump(attribute_type, value, attribute.constraints))
      else
        acc
      end
    end)
  end
end
