defmodule AshNeo4j.DataLayer.Info do
  @moduledoc "Introspection helpers for AshNeo4j.DataLayer"

  alias Spark.Dsl.Extension

  @spec label(Ash.Resource.t()) :: atom() | nil
  def label(resource) do
    Extension.get_opt(resource, [:neo4j], :label, nil, true)
  end

  @spec store(Ash.Resource.t()) :: list() | nil
  def store(resource) do
    Extension.get_opt(resource, [:neo4j], :store, [], true)
  end

  @spec translate(Ash.Resource.t()) :: keyword() | nil
  def translate(resource) do
    Extension.get_opt(resource, [:neo4j], :translate, [], true)
  end

  @spec relate(Ash.Resource.t()) :: list(tuple()) | nil
  def relate(resource) do
    Extension.get_opt(resource, [:neo4j], :relate, [], true)
  end

  @spec node_relationship(Ash.Resource.t(), atom() | String.t()) :: list(tuple) | nil
  def node_relationship(resource, source_attribute) do
    List.keyfind(relate(resource), String.to_atom(source_attribute), 0)
  end

  @doc"""
  Returns any matching Ash.Resource.Info relationship given relationship and destination node labels
  """
  @spec relationship(Ash.Resource.t(), atom(), atom()) :: struct() | nil
  def relationship(resource, relationship_label, dest_label) when is_atom(resource) and is_atom(relationship_label) and is_atom(dest_label) do
    #IO.inspect(resource, label: "Info.relationship resource")
    #IO.inspect(relationship_label, label: "Info.relationship relationship_label")
    #IO.inspect(dest_label, label: "Info.relationship dest_label")
    relationships = Enum.into(relate(resource), [], fn {relationship_name, edge_label, _edge_direction} ->
      relationship = Ash.Resource.Info.relationship(resource, relationship_name)
      relationship_destination_label = Module.split(relationship.destination) |> List.last() |> String.to_atom() |> IO.inspect(label: :relationship_destination_label)
      if relationship != nil && relationship_label == edge_label && dest_label == relationship_destination_label do
        relationship
      end
    end)
    if length(relationships) == 1 do
      List.first(relationships)
    else
      nil
    end
    |> IO.inspect(label: "Info.relationship result")
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
