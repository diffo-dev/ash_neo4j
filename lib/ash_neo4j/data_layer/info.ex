defmodule AshNeo4j.DataLayer.Info do
  @moduledoc "Introspection helpers for AshNeo4j.DataLayer"

  alias Spark.Dsl.Extension

  def label(resource) do
    Extension.get_opt(resource, [:neo4j], :label, nil, true)
  end

  def store(resource) do
    Extension.get_opt(resource, [:neo4j], :store, [], true)
  end

  def translate(resource) do
    Extension.get_opt(resource, [:neo4j], :translate, [], true)
  end

  def resource(label) do
    #TODO: this should be a reverse lookup, may need to be done using a protocol implemented by the generated node?
    case label do
      :Post -> AshNeo4j.Test.Resource.Post
      :Comment -> AshNeo4j.Test.Resource.Comment
      _ -> nil
    end
  end

  @doc """
  Converts an Ash.Query.Ref to a node property name string, translating if necessary
  """
  @spec convert_to_property_name(Ash.Resource.t(), Ash.Query.Ref.t()) :: String.t() | nil
  def convert_to_property_name(resource, ash_query_ref) do
    #IO.inspect(ash_query_ref, label: "AshNeo4j.DataLayer.convert_to_property_name ash_query_ref")
    attribute_name = Ash.Query.Ref.name(ash_query_ref)
    translate = translate(resource)
    case Keyword.get(translate, attribute_name) do
      nil -> attribute_name
      resource_name -> resource_name
    end
    |> to_string()
    #|> IO.inspect(label: "AshNeo4j.DataLayer.convert_to_property_name result")
  end

  @doc """
  Converts a keyword list (such as resource predicates) such that the resulting keyword list
  only contains keywords that are valid node properties (i.e. stored attributes and translated attributes)
  """
  def convert_resource_to_node_keys(resource, keywords) do
    store = store(resource)
    translate = translate(resource)
    Enum.into(keywords, [], fn {key, value} ->
      if Enum.member?(store, key) do
        {key, value}
      else
        case Keyword.get(translate, key) do
          nil -> nil
          translated_key -> {translated_key, value}
        end
      end
    end)
    |> IO.inspect(label: "AshNeo4j.DataLayer.convert_resource_to_node_keys result")
  end
end
