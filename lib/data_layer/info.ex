defmodule AshNeo4j.DataLayer.Info do
  @moduledoc "Introspection helpers for AshNeo4j.DataLayer"

  alias Spark.Dsl.Extension

  @spec label(Ash.Resource.t()) :: atom() | nil
  def label(resource) do
    Extension.get_opt(resource, [:neo4j], :label, nil, true)
  end

  @spec relate(Ash.Resource.t()) :: list(tuple()) | nil
  def relate(resource) do
    Extension.get_opt(resource, [:neo4j], :relate, [], true)
  end

  @spec skip(Ash.Resource.t()) :: list() | nil
  def skip(resource) do
    Extension.get_opt(resource, [:neo4j], :skip, [], true)
  end

  @spec translate(Ash.Resource.t()) :: keyword() | nil
  def translate(resource) do
    Extension.get_opt(resource, [:neo4j], :translate, [], true)
  end

  @spec translation(Ash.Resource.t()) :: keyword() | nil
  def translation(resource) do
    Extension.get_opt(resource, [:neo4j], :translation, [], true)
  end

  @spec node_relationship(Ash.Resource.t(), atom() | String.t()) :: tuple() | nil
  def node_relationship(resource, source_attribute) when is_atom(source_attribute) do
    List.keyfind(relate(resource), source_attribute, 0)
  end

  def node_relationship(resource, source_attribute) when is_bitstring(source_attribute) do
    List.keyfind(relate(resource), String.to_atom(source_attribute), 0)
  end

  @doc """
  Returns any matching Ash.Resource.Info relationship given relationship and destination node labels
  """
  @spec relationship(Ash.Resource.t(), atom(), atom()) :: struct() | nil
  def relationship(resource, relationship_label, dest_label)
      when is_atom(resource) and is_atom(relationship_label) and is_atom(dest_label) do
    relationships =
      Enum.into(relate(resource), [], fn {relationship_name, edge_label, _edge_direction} ->
        relationship = Ash.Resource.Info.relationship(resource, relationship_name)
        relationship_destination_label = Module.split(relationship.destination) |> List.last() |> String.to_atom()

        if relationship != nil && relationship_label == edge_label && dest_label == relationship_destination_label do
          relationship
        end
      end)

    hd(relationships)
    # |> IO.inspect(label: "Info.relationship result")
  end

  @doc """
  Returns the source node property name given the source resource and destination attribute name, i.e. post_id returns uuid
  """
  @spec source_node_property_name(Ash.Resource.t(), atom(), atom()) :: atom() | nil
  def source_node_property_name(source_resource, dest_resource, dest_attribute_name)
      when is_atom(source_resource) and is_atom(dest_resource) and is_atom(dest_attribute_name) do
    # TODO use dest resource to figure out the dest_prefix
    dest_prefix = String.downcase("#{Ash.Resource.Info.short_name(source_resource)}_")
    attribute_name = String.to_atom(String.replace_leading(Atom.to_string(dest_attribute_name), dest_prefix, ""))
    translation(source_resource)
    |> Keyword.get(attribute_name, attribute_name)
  end

  @doc """
  Converts an attribute name to a node property name string, translating if necessary
  The attribute name can be an Ash.Query.Ref or atom
  """
  @spec convert_to_property_name(Ash.Resource.t(), struct()) :: String.t() | nil
  def convert_to_property_name(resource, ash_query_ref) when is_struct(ash_query_ref, Ash.Query.Ref) do
    attribute_name = Ash.Query.Ref.name(ash_query_ref)
    convert_to_property_name(resource, attribute_name)
  end

  @spec convert_to_property_name(Ash.Resource.t(), atom()) :: String.t() | nil
  def convert_to_property_name(resource, attribute_name) when is_atom(attribute_name) do
    translation(resource)
    |> Keyword.get(attribute_name, attribute_name)
    |> to_string()
  end
end
