defmodule AshNeo4j.DataLayer do
  @moduledoc "Ash DataLayer for Neo4j"

  @behaviour Ash.DataLayer

  alias Ash.Actions.Sort
  alias AshNeo4j.DataLayer.Info
  alias AshNeo4j.QueryHelper
  alias AshNeo4j.Neo4jHelper
  alias AshNeo4j.DataLayer.Cast

  @filter_stream_size 100

  @impl true
  def can?(_, :read), do: true
  def can?(_, :create), do: true
  #def can?(_, :update), do: true
  #def can?(_, :upsert), do: true
  #def can?(_, :destroy), do: true
  def can?(_, :sort), do: true
  def can?(_, :filter), do: true
  def can?(_, :limit), do: true
  # def can?(_, :bulk_create), do: true
  def can?(_, :offset), do: true
  def can?(_, :boolean_filter), do: true
  #def can?(_, :transact), do: true
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
        label :Comment
        store [:title]
        translate id: :uuid
        relate [{:post, :BELONGS_TO, :outgoing}]
      end
      """
    ],
    schema: [
      label: [
        type: :atom,
        doc: "The node label",
        required: true
      ],
      store: [
        type: {:list, :atom},
        doc: "The attributes to be stored as node properties, without translation",
        required: true
      ],
      translate: [
        type: :keyword_list,
        doc: "Optional attribute to node property translations"
      ],
      relate: [
        type: {:list, @node_relationship},
        doc: "Optional list of node relationships, as tuples of {relationship_name, edge_label, edge_direction}"
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
    persisters: [AshNeo4j.DataLayer.Transformer]

  defmodule Query do
    @moduledoc false
    defstruct [:resource, :sort, :filter, :limit, :offset, :domain]
  end

  @impl true
  @spec run_query(any(), atom()) :: {:error, any()} | {:ok, any()}
  def run_query(query, _resource) do
    #IO.inspect(query, label: "AshNeo4j.DataLayer.run_query query")
    case QueryHelper.query_nodes(query) do
      {:error, error} ->
        {:error, error}
      {:ok, nodes} ->
        results =
          convert_nodes_to_resources(query.resource, nodes)
          |> filter_stream(query.domain, query.filter)
          |> sort_stream(query.resource, query.domain, query.sort)
          |> offset_stream(query.offset)
          |> limit_stream(query.limit)
          #|> IO.inspect(label: "AshNeo4j.DataLayer.run_query result")
        {:ok, results}
    end

  end

  @impl true
  def create(resource, changeset) do
    case run_query(%Query{resource: resource}, resource) do
      {:ok, records} ->
        create_from_records(records, resource, changeset, false)
      {:error, _} ->
        {:error, "create failed"}
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
    #IO.inspect(filter, label: "AshNeo4j.DataLayer.filter_matches filter")
    {:ok, records} = Ash.Filter.Runtime.filter_matches(domain, records, filter)
    deduplicate(filter.resource, records)
  end

  # deduplicates records by primary key
  defp deduplicate(resource, records) when is_atom(resource) and is_list(records) do
    if length(records) > 1 do
      #IO.inspect(records, label: "AshNeo4j.DataLayer.deduplicate records")
      primary_keys = Ash.Resource.Info.primary_key(resource) #|> IO.inspect(label: "AshNeo4j.DataLayer.deduplicate keys")
      case length(primary_keys) do
        1 ->
          #primary_key = List.first(primary_keys)
          Enum.into(records, %{}, fn record ->
            composite_key_value = Enum.map_join(primary_keys, "_", fn primary_key -> Map.get(record, primary_key) end)
            {composite_key_value, record} end)
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
    #|> IO.inspect(label: "AshNeo4j.DataLayer.convert_nodes_to_resources groups")
    |> Stream.map(fn related_nodes ->
      source_node = Map.get(related_nodes, "s")
      edge = Map.get(related_nodes, "r")
      dest_node = Map.get(related_nodes, "d")
      if edge != nil && dest_node != nil do
        # enrich the source node
        dest_label = String.to_atom(List.first(dest_node.labels))
        relationship_label = String.to_atom(edge.type)
        relationship = Info.relationship(resource, relationship_label, dest_label)
        if (relationship != nil) do
          dest_resource = convert_node_to_resource(relationship.destination, dest_node, [])
          enrichment = {relationship.source_attribute, Map.get(dest_resource, relationship.destination_attribute)}
          convert_node_to_resource(resource, source_node, [enrichment])
          #|> IO.inspect(label: :enriched_source_resource)
        else
          IO.puts("unable to enrich source node")
          convert_node_to_resource(resource, source_node)
        end
      else
        convert_node_to_resource(resource, source_node)
      end
      #|> IO.inspect(label: "AshNeo4j.DataLayer.convert_nodes_to_resources result")
    end)
  end

  defp convert_node_to_resource(resource, node, enrichments \\ []) when is_atom(resource) and is_map(node) and is_list(enrichments) do
    #IO.inspect(node, label: "AshNeo4j.DataLayer.convert_node_to_resource node")
    enriched = Enum.into(enrichments, %{}, fn {field, value} ->
      {field, value}
    end) #|> IO.inspect(label: :enriched)
    # stored or translated fields will overwrite enrichments
    stored = Enum.into(Info.store(resource), enriched, fn field ->
      property_value = Map.get(node.properties, to_string(field))
      {field, Cast.cast(resource, field, property_value)}
    end) #|> IO.inspect(label: :stored)
    Enum.into(Info.translate(resource), stored, fn {resource_field, node_field} ->
      property_value = Map.get(node.properties, to_string(node_field))
      {resource_field, Cast.cast(resource, resource_field, property_value)}
    end)
    #|> IO.inspect(label: "AshNeo4j.DataLayer.convert_node_to_resource translated")
    |> Map.put(:__struct__, resource)
    |> Map.put(:__data_layer__, __MODULE__)
    # TODO metadata should be a struct including neo4j node id?
    |> Map.put(:__metadata__, %{})
    |> Map.put(:aggregates, %{})
    |> Map.put(:calculations, %{})
    #|> IO.inspect(label: "AshNeo4j.DataLayer.convert_node_to_resource result")
  end

  defp sort_stream(stream, _resource, _domain, sort) when sort in [nil, []] do
    stream
  end

  defp sort_stream(stream, resource, domain, sort) do
    Sort.runtime_sort(stream, sort, domain: domain, resource: resource)
  end

  defp filter_stream(stream, _domain, nil), do: stream

  defp filter_stream(stream, domain, filter) do
    stream
    |> Stream.chunk_every(@filter_stream_size)
    |> Stream.flat_map(fn chunk ->
      filter_matches(chunk, filter, domain)
    end)
  end

  defp offset_stream(stream, offset) when offset in [0, nil], do: stream
  defp offset_stream(stream, offset), do: Stream.drop(stream, offset)

  defp limit_stream(stream, nil), do: stream
  defp limit_stream(stream, limit), do: Stream.take(stream, limit)

  defp create_from_records(records, resource, changeset, _retry?) do
    IO.inspect(records, label: "create_from_records records")
    IO.inspect(changeset, label: "create_from_records changeset")
    pkey = Ash.Resource.Info.primary_key(resource)
    pkey_value = Map.take(changeset.attributes, pkey)
    if (pkey_value == nil) do
      IO.puts("warning: pkey #{pkey} is nil")
    end
    if Enum.find(records, fn record -> Map.take(record, pkey) == pkey_value end) do
      {:error, "Record is not unique"}
    else
      create_from_attributes(resource, changeset.attributes)
    end
  end

  defp create_from_attributes(resource, attributes) when is_atom(resource) and is_map(attributes) do
    store = Info.store(resource)
    stored = Enum.into(store, %{}, fn field-> {field, Map.get(attributes, field)} end)
    translate = Info.translate(resource)
    properties = Enum.into(translate, stored, fn {resource_field, node_field} ->
      {node_field, Map.get(attributes, resource_field)} end)
    case Info.label(resource) |> Neo4jHelper.create_node(properties) do
      {:ok, %Boltx.Response{results: [ node_map | _ ]}} ->
        node = Map.get(node_map, "n")
        {:ok, convert_node_to_resource(resource, node)}
      {:error, error} ->
        {:error, error}
    end
  end
end
