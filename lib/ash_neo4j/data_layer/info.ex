defmodule AshNeo4j.DataLayer.Info do
  @moduledoc "Introspection helpers for AshNeo4j.DataLayer"

  alias Spark.Dsl.Extension

  @spec label(Ash.Resource.t()) :: atom() | nil
  def label(resource) do
    Extension.get_opt(resource, [:neo4j], :label, nil, true)
  end

  @spec label(Ash.Resource.t()) :: list() | nil
  def store(resource) do
    Extension.get_opt(resource, [:neo4j], :store, [], true)
  end

  @spec label(Ash.Resource.t()) :: keyword() | nil
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
  Converts an attribute name to a node property name string, translating if necessary
  The attribute name can be an Ash.Query.Ref or atom
  """
  @spec convert_to_property_name(Ash.Resource.t(), struct()) :: String.t() | nil
  def convert_to_property_name(resource, ash_query_ref) when is_struct(ash_query_ref) do
    attribute_name = Ash.Query.Ref.name(ash_query_ref)
    convert_to_property_name(resource, attribute_name)
  end

  @spec convert_to_property_name(Ash.Resource.t(), atom()) :: String.t() | nil
  def convert_to_property_name(resource, attribute_name) when is_atom(attribute_name) do
    translate = translate(resource)
    case Keyword.get(translate, attribute_name) do
      nil -> attribute_name
      resource_name -> resource_name
    end
    |> to_string()
  end
end
