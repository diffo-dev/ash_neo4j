defmodule AshNeo4j.DataLayer do
  @moduledoc "Ash DataLayer for Neo4j"

  @behaviour Ash.DataLayer

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
  def can?(_, :expression_calculation_sort), do: true
  def can?(_, {:sort, _}), do: true
  def can?(_, _), do: false

  @node_relationship {:tuple, [:atom, :atom, :atom]}

  @neo4j %Spark.Dsl.Section{
    name: :neo4j,
    examples: [
      """
      neo4j do
        store [:title]
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
      skip: [
        type: {:list, :atom},
        doc: "Optional list of attributes not to be stored directly as node properties",
        required: false
      ],
      translate: [
        type: :keyword_list,
        doc: "Optional list of attribute to node property translations"
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
      AshNeo4j.Verifiers.VerifyIdTranslated,
      AshNeo4j.Verifiers.VerifyRelate,
      AshNeo4j.Verifiers.VerifyPropertiesCamelCase
    ],
    transformers: [
      AshNeo4j.Transformers.TransformEnsureLabelled,
      AshNeo4j.Transformers.TransformAddTranslation
    ]

  defmodule Query do
    @moduledoc false
    defstruct [:resource, :sort, :filter, :limit, :offset, :domain]
  end

  @impl true
  @spec run_query(any(), atom()) :: {:error, any()} | {:ok, any()}
  def run_query(query, _resource) do
    # IO.inspect(query, label: "AshNeo4j.DataLayer.run_query query")
    case QueryHelper.query_nodes(query) do
      {:error, error} ->
        {:error, error}

      {:ok, []} ->
        {:ok, []}

      {:ok, nodes} ->
        # IO.inspect(nodes, label: "AshNeo4j.DataLayer.run_query nodes")
        results =
          convert_nodes_to_resources(query.resource, nodes)
          |> filter_stream(query.domain, query.filter)
          |> Enum.to_list()

        {:ok, results}
    end

    # |> IO.inspect(label: "AshNeo4j.DataLayer.run_query result")
  end

  @impl true
  def create(resource, changeset) do
    create_from_changeset(nil, resource, changeset)
  end

  @impl true
  def upsert(resource, changeset, keys) do
    id_properties = id_properties(resource, changeset.attributes)

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
  end

  @impl true
  def update(resource, changeset) do
    update_from_changeset(nil, resource, changeset)
  end

  @impl true
  def destroy(resource, changeset) do
    destroy_record(resource, changeset.data)
  end

  defp destroy_record(resource, record) do
    label = AshNeo4j.DataLayer.Info.label(resource)
    id_properties = id_properties(resource, record)

    case Neo4jHelper.delete_nodes(label, id_properties) do
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

  def filter_matches(records, nil, _domain), do: records

  def filter_matches(records, filter, domain) do
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

  # converts nodes to resources, where the input is a list of related node groups
  # the output of each group is a single resource, enriched with attributes linking related nodes
  defp convert_nodes_to_resources(resource, groups) when is_atom(resource) and is_list(groups) do
    groups
    # |> IO.inspect(label: "AshNeo4j.DataLayer.convert_nodes_to_resources groups")
    |> Stream.map(fn related_nodes ->
      source_node = Map.get(related_nodes, "s")
      edge = Map.get(related_nodes, "r")
      dest_node = Map.get(related_nodes, "d")

      if edge != nil && dest_node != nil do
        # enrich the source node
        dest_label = String.to_atom(List.first(dest_node.labels))
        relationship_label = String.to_atom(edge.type)
        relationship = Info.relationship(resource, relationship_label, dest_label)

        if relationship != nil do
          dest_resource = convert_node_to_resource(relationship.destination, dest_node, [])
          enrichment = {relationship.source_attribute, Map.get(dest_resource, relationship.destination_attribute)}
          convert_node_to_resource(resource, source_node, [enrichment])
        else
          IO.puts("unable to enrich source node")
          convert_node_to_resource(resource, source_node)
        end
      else
        convert_node_to_resource(resource, source_node)
      end

      # |> IO.inspect(label: "AshNeo4j.DataLayer.convert_nodes_to_resources result")
    end)
  end

  defp convert_node_to_resource(resource, node, enrichments \\ [])
       when is_atom(resource) and is_map(node) and is_list(enrichments) do
    # IO.inspect(node, label: "AshNeo4j.DataLayer.convert_node_to_resource node")
    enriched =
      Enum.into(enrichments, %{}, fn {field, value} ->
        {field, value}
      end)

    Enum.into(Info.translation(resource), enriched, fn {resource_field, node_field} ->
      property_value = Map.get(node.properties, to_string(node_field))
      {resource_field, Cast.cast(resource, resource_field, property_value)}
    end)
    # |> IO.inspect(label: "AshNeo4j.DataLayer.convert_node_to_resource translated")
    |> Map.put(:__struct__, resource)
    |> Map.put(:__data_layer__, __MODULE__)
    # TODO metadata should be a struct including neo4j node id?
    |> Map.put(:__metadata__, %{})
    |> Map.put(:aggregates, %{})
    |> Map.put(:calculations, %{})

    # |> IO.inspect(label: "AshNeo4j.DataLayer.convert_node_to_resource result")
  end

  defp filter_stream(stream, _domain, nil), do: stream

  defp filter_stream(stream, domain, filter) do
    stream
    |> Stream.chunk_every(@filter_stream_size)
    |> Stream.flat_map(fn chunk ->
      filter_matches(chunk, filter, domain)
    end)
  end

  defp create_from_changeset(_records, resource, changeset) do
    # don't use records yet, but expect to for upsert
    primary_keys = Ash.Resource.Info.primary_key(resource)
    id_attributes = Map.take(changeset.attributes, primary_keys)

    if Enum.empty?(id_attributes) do
      {:error, "no values supplied for primary keys #{primary_keys}"}
    else
      create_from_attributes(resource, changeset.attributes)
    end
  end

  defp create_from_attributes(resource, attributes) when is_atom(resource) and is_map(attributes) do
    properties = properties(resource, attributes)

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
