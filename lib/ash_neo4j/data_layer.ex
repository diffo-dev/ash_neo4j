defmodule AshNeo4j.DataLayer do
  @behaviour Ash.DataLayer

  alias Ash.Actions.Sort

  @filter_stream_size 100

  @impl true
  def can?(_, :read), do: true
  #def can?(_, :create), do: true
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

  @neo4j %Spark.Dsl.Section{
    name: :neo4j,
    examples: [
      """
      neo4j do
        label :Comment
        store [:title]
        translate id: :uuid
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

  @moduledoc """
  The data layer implementation for AshNeo4j
  """
  use Spark.Dsl.Extension,
    sections: @sections,
    persisters: [AshNeo4j.DataLayer.Transformers.BuildParser]

  defmodule Query do
    @moduledoc false
    defstruct [:resource, :sort, :filter, :limit, :offset, :domain]
  end

  @impl true
  def run_query(query, resource) do
    IO.inspect(query, label: "AshNeo4j.DataLayer.run_query query")
    label = AshNeo4j.DataLayer.Info.label(resource)
    IO.inspect(label, label: "AshNeo4j.DataLayer.run_query label")
    module = Module.concat(Node, label)
    nodes = AshNeo4j.Ex4j.Helper.match_nodes(module, query)
    results =
      nodes
      |> Stream.map(fn record ->
        record
        |> Map.get(to_string(label))
        |> convert_node_to_resource(resource)
      end)
      |> filter_stream(query.domain, query.filter)
      |> sort_stream(resource, query.domain, query.sort)
      |> offset_stream(query.offset)
      |> limit_stream(query.limit)
      |> IO.inspect(label: "AshNeo4j.DataLayer.run_query result")
    {:ok, results}
  end

  @impl true
  def resource_to_query(resource, domain) do
    %Query{resource: resource, domain: domain}
  end

  @impl true
  def transaction(resource, fun, _timeout, _) do
    label = AshNeo4j.DataLayer.Info.label(resource)

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
    throw({{:neo4j_rollback, AshNeo4j.DataLayer.Info.label(resource)}, error})
  end

  @impl true
  def in_transaction?(resource) do
    Process.get({:neo4j_in_transaction, AshNeo4j.DataLayer.Info.label(resource)}, false) == true
  end

  def filter_matches(records, nil, _domain), do: records

  def filter_matches(records, filter, domain) do
    {:ok, records} = Ash.Filter.Runtime.filter_matches(domain, records, filter)
    records
  end

  defp convert_node_to_resource(node, resource) when is_map(node) do
    store = AshNeo4j.DataLayer.Info.store(resource)
    translate = AshNeo4j.DataLayer.Info.translate(resource)
    stored_fields = Enum.into(store, %{}, fn field ->
      {field, Map.get(node, field)}
    end)
    Enum.into(translate, stored_fields, fn {resource_field, node_field} ->
      {resource_field, Map.get(node, node_field)}
    end)
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
end
