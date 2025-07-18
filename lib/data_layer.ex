defmodule AshNeo4j.DataLayer do
  @moduledoc "Ash DataLayer for Neo4j"

  @behaviour Ash.DataLayer

  require Logger
  alias AshNeo4j.DataLayer.Info
  alias AshNeo4j.QueryHelper
  alias AshNeo4j.Neo4jHelper
  alias AshNeo4j.DataLayer.Cast

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
  def can?(_, :expression_calculation), do: true
  # def can?(_, :expression_calculation_sort), do: true
  def can?(_, {:sort, _}), do: true
  def can?(_, _), do: false

  @node_relationship {:tuple, [:atom, :atom, :atom]}

  @neo4j %Spark.Dsl.Section{
    name: :neo4j,
    examples: [
      """
      neo4j do
        label [:Comment]
        translate id: :uuid
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
        type: {:list, @node_relationship},
        doc: "Optional list of node relationships, as tuples of {relationship_name, edge_label, edge_direction}"
      ],
      translate: [
        type: :keyword_list,
        doc: "Optional list of attribute to node property translations"
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

  @impl true
  def add_calculation(query, calculation, _expression, _resource) do
    # TODO check calculation involves node properties, can be from related nodes if loaded
    {:ok, Map.put(query, :calculations, [calculation | query.calculations])}
    # |> IO.inspect(label: :add_calculation_result)
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
      AshNeo4j.Verifiers.VerifyIdTranslated,
      AshNeo4j.Verifiers.VerifyRelate,
      AshNeo4j.Verifiers.VerifyPropertiesCamelCase
    ],
    transformers: [
      AshNeo4j.Transformers.TransformEnsureLabelled,
      AshNeo4j.Transformers.TransformAddTranslation,
      AshNeo4j.Transformers.TransformAddRelationshipAttributes
    ]

  defmodule Query do
    @moduledoc false
    defstruct [:resource, :sort, :filter, :limit, :offset, :domain, calculations: []]
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

    result = update_from_changeset(nil, resource, changeset)

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

    destroy_record(resource, changeset.data)
  end

  defp destroy_record(resource, record) do
    label = Info.label(resource)
    id_properties = id_properties(resource, record)
    # preserve_relationships = Info.preserve_relationships(resource)

    case Neo4jHelper.safe_delete_nodes(label, id_properties, []) do
      {:ok, _} ->
        :ok

      {:error, error} ->
        {:error, error}
    end
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
    # IO.inspect(filter, label: "AshNeo4j.DataLayer.filter_matches filter")
    {:ok, records} = Ash.Filter.Runtime.filter_matches(domain, records, filter)
    deduplicate(filter.resource, records)
  end

  # deduplicates records by primary key
  defp deduplicate(resource, records) when is_atom(resource) and is_list(records) do
    if length(records) > 1 do
      # IO.inspect(records, label: "AshNeo4j.DataLayer.deduplicate records")
      # |> IO.inspect(label: "AshNeo4j.DataLayer.deduplicate keys")
      primary_keys = Ash.Resource.Info.primary_key(resource)

      case length(primary_keys) do
        1 ->
          # primary_key = List.first(primary_keys)
          Enum.into(records, %{}, fn record ->
            composite_key_value = Enum.map_join(primary_keys, "_", fn primary_key -> Map.get(record, primary_key) end)
            {composite_key_value, record}
          end)
          |> Map.values()

        # |> IO.inspect(label: "AshNeo4j.DataLayer.deduplicate result")
        _ ->
          # TODO handle composite primary key
          records
      end
    else
      records
    end
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

    # |> IO.inspect(label: :consolidate_groups_result)
  end

  # converts nodes to resources, where the input is a list of related node groups
  # the output of each group is a single resource, enriched with attributes linking related nodes
  defp convert_groups_to_resources(query, groups) when is_struct(query, Query) and is_list(groups) do
    # |> IO.inspect(label: "AshNeo4j.DataLayer.convert_groups_to_resources groups")
    consolidate_groups(groups)
    |> Stream.map(&convert_to_resource(query, &1))

    # |> IO.inspect(label: "AshNeo4j.DataLayer.convert_groups_to_resources result")
  end

  defp convert_to_resource(query, consolidated_group)
       when is_struct(query, Query) and is_tuple(consolidated_group) do
    # IO.inspect(consolidated_group, label: "AshNeo4j.DataLayer.convert_to_resource consolidated_group")
    source_node = elem(consolidated_group, 0)
    related = elem(consolidated_group, 1)

    enrichments =
      Enum.reduce(related, [], &enrichments(query.resource, &2, &1))
      # |> IO.inspect(label: :enrichments_pre_consolidation)
      |> consolidate_enrichments()

    # |> IO.inspect(label: :enrichments)

    convert_node_to_resource(query.resource, source_node, enrichments)
    |> evaluate_calculations(query)

    # |> IO.inspect(label: "AshNeo4j.DataLayer.convert_to_resource result with calculations")
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
    # IO.inspect(resource, label: :enrichment_resource)
    # IO.inspect(edge, label: :enrichment_edge)
    # IO.inspect(dest_node, label: :enrichment_dest_node)
    dest_label = String.to_atom(List.first(dest_node.labels))
    relationship_label = String.to_atom(edge.type)
    relationship = Info.relationship(resource, relationship_label, dest_label)

    if relationship != nil do
      # IO.inspect(relationship, label: :enrichment_relationship)
      reverse_node_relationship = Info.reverse_node_relationship(resource, relationship.name)

      reverse_relationship =
        cond do
          reverse_node_relationship == nil ->
            nil

          true ->
            Ash.Resource.Info.relationship(relationship.destination, elem(reverse_node_relationship, 0))
        end

      cond do
        relationship.cardinality == :many ->
          dest_resource = convert_node_to_resource(relationship.destination, dest_node, [])
          [{relationship.name, [dest_resource]} | acc]

        relationship.cardinality == :one && relationship.type == :belongs_to ->
          dest_resource = convert_node_to_resource(relationship.destination, dest_node, [])

          destination_property =
            Info.convert_to_property_name(relationship.destination, relationship.destination_attribute)

          [
            {relationship.name, dest_resource},
            {relationship.source_attribute, Map.get(dest_node.properties, destination_property)} | acc
          ]

        reverse_relationship != nil &&
            (reverse_relationship.cardinality == :one && reverse_relationship.type == :has_one) ->
          dest_resource = convert_node_to_resource(relationship.destination, dest_node, [])
          source_property = Info.convert_to_property_name(relationship.source, relationship.source_attribute)
          # |> IO.inspect(label: :enrichment_source_property)
          [
            {reverse_relationship.name, dest_resource},
            {relationship.destination_attribute, Map.get(dest_node.properties, source_property)} | acc
          ]

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

    # |> IO.inspect(label: :enrichments)
  end

  defp convert_node_to_resource(resource, node, enrichments \\ [])
       when is_atom(resource) and is_map(node) and is_list(enrichments) do
    # IO.inspect(node, label: "AshNeo4j.DataLayer.convert_node_to_resource node")

    enriched =
      Enum.into(enrichments, %{}, fn {field, value} ->
        {field, value}
      end)

    fields =
      Enum.into(Info.translation(resource), enriched, fn {resource_field, node_field} ->
        property_value = Map.get(node.properties, to_string(node_field))
        {resource_field, Cast.cast(resource, resource_field, property_value)}
      end)

    struct!(resource, fields)
    |> Ash.Resource.set_metadata(%{node_id: node.id, data_layer: __MODULE__, labels: node.labels})
    |> Ash.Resource.set_meta(struct(Ecto.Schema.Metadata, state: :loaded))

    # |> IO.inspect(label: "AshNeo4j.DataLayer.convert_node_to_resource result")
  end

  defp evaluate_calculations(resource_instance, query) when is_struct(resource_instance) and is_struct(query, Query) do
    query.calculations
    |> Enum.reverse()
    |> Enum.reduce(
      resource_instance,
      fn calculation, acc ->
        # allow calculations to chain previous results
        expression = Keyword.get(calculation.opts, :expr, %Ash.NotLoaded{})
        opts = [resource: query.resource, record: acc]
        Map.put(acc, calculation.name, Ash.Expr.eval!(expression, opts))
      end
    )
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
    properties = properties(resource, attributes)
    relationship_attributes = Info.relationship_attributes(resource) |> Keyword.delete(:id)
    relationship_source_attributes = Map.take(attributes, Keyword.keys(relationship_attributes))

    case Enum.count(relationship_source_attributes) do
      0 ->
        create_node(resource, properties)

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
                {^name, edge_label, edge_direction} ->
                  dest_node_property_name =
                    Keyword.get(Info.translation(dest_resource), relationship.destination_attribute)

                  dest_id_value = Map.get(relationship_source_attributes, source_attribute)

                  if dest_id_value == nil do
                    acc
                  else
                    dest_id = %{dest_node_property_name => dest_id_value}
                    [{Info.label(dest_resource), dest_id, edge_label, edge_direction} | acc]
                  end

                nil ->
                  acc
              end
            end
          )

        # create_node_with_relationships
        case Neo4jHelper.create_node_with_relationships(Info.label(resource), properties, relationships) do
          {:ok, %Boltx.Response{results: groups}} ->
            consolidated_groups = consolidate_groups(groups)
            # return the enriched created resource
            cond do
              length(consolidated_groups) == 1 ->
                query = resource_to_query(resource, Ash.Resource.Info.domain(resource))
                resource = convert_to_resource(query, hd(consolidated_groups))
                # |> IO.inspect(label: :enriched_resource)
                {:ok, resource}

              true ->
                {:error, "expected groups to consolidate to a single group (resource)"}
            end

          {:error, error} ->
            {:error, error}
        end
    end
  end

  defp create_node(resource, properties) when is_atom(resource) and is_map(properties) do
    case Info.label(resource) |> Neo4jHelper.create_node(properties) do
      {:ok, %Boltx.Response{results: [node_map | _]}} ->
        node = Map.get(node_map, "n")
        {:ok, convert_node_to_resource(resource, node)}

      {:error, error} ->
        {:error, error}
    end
  end

  defp update_from_changeset(_records, dest_resource, changeset)
       when is_atom(dest_resource) and is_struct(changeset, Ash.Changeset) do
    dest_id = id_properties(dest_resource, changeset.data)
    update_properties = properties(dest_resource, changeset.attributes)
    remove_properties = remove_properties(dest_resource, changeset.attributes)

    cond do
      accessing_from = Map.get(changeset.context, :accessing_from) ->
        # update relationship

        # relate nodes, for example Comment resource, changeset.attributes: %{post_id: "5d5fcf34-f6cc-461b-9867-5da7b6f6ae44"}
        # where changeset.context: %{accessing_from: %{name: :comments, source: AshNeo4j.Test.Resource.Post}}
        dest_label = Info.label(dest_resource)
        source_resource = Map.get(accessing_from, :source)
        source_label = Info.label(source_resource)
        source_attribute_name = Map.get(accessing_from, :name)
        dest_attribute_name = hd(Map.keys(changeset.attributes))
        source_node_property_name = Info.source_node_property_name(source_resource, dest_resource, dest_attribute_name)
        node_relationship = Info.node_relationship(source_resource, source_attribute_name)

        case node_relationship do
          nil ->
            {:error, "node relationship interdeterminate"}

          {_relationship_name, edge_label, edge_direction} ->
            if Map.get(accessing_from, :unrelating?) do
              # unrelate using source attribute in changeset.data
              source_id = %{source_node_property_name => Map.get(changeset.data, dest_attribute_name)}

              case Neo4jHelper.unrelate_nodes(source_label, source_id, dest_label, dest_id, edge_label, edge_direction) do
                {:ok, %Boltx.Response{results: [node_map | _]}} ->
                  node = Map.get(node_map, "d")
                  {:ok, convert_node_to_resource(dest_resource, node)}

                {:error, error} ->
                  {:error, error}
              end
            else
              # relate using source attribute value in changeset.attribute
              source_id = %{source_node_property_name => Map.get(changeset.attributes, dest_attribute_name)}

              case Neo4jHelper.relate_nodes(source_label, source_id, dest_label, dest_id, edge_label, edge_direction) do
                {:ok, %Boltx.Response{results: [node_map | _]}} ->
                  node = Map.get(node_map, "d")
                  {:ok, convert_node_to_resource(dest_resource, node)}

                {:error, error} ->
                  {:error, error}
              end
            end
        end

      !Enum.empty?(update_properties) or !Enum.empty?(remove_properties) ->
        # update properties
        case Info.label(dest_resource) |> Neo4jHelper.update_node(dest_id, update_properties, remove_properties) do
          {:ok, %Boltx.Response{results: [node_map | _]}} ->
            node = Map.get(node_map, "n")
            {:ok, convert_node_to_resource(dest_resource, node)}

          {:error, error} ->
            {:error, error}
        end
    end
  end

  defp id_properties(resource, map) when is_atom(resource) and is_map(map) do
    primary_keys = Ash.Resource.Info.primary_key(resource)
    translation = Info.translation(resource)
    Enum.into(primary_keys, %{}, fn key -> {Keyword.get(translation, key, key), Map.get(map, key)} end)
  end

  defp properties(resource, map) when is_atom(resource) and is_map(map) do
    Info.translation(resource)
    |> Enum.into(%{}, fn {key, translated_key} -> {translated_key, Map.get(map, key)} end)
    |> Map.reject(fn {_k, v} -> v == nil end)
  end

  defp remove_properties(resource, map) when is_atom(resource) and is_map(map) do
    map
    |> Map.reject(fn {_k, v} -> v != nil end)
    |> Enum.into([], fn {field, _} -> Keyword.get(Info.translation(resource), field, nil) end)
    |> Enum.reject(fn field -> field == nil end)
  end
end
