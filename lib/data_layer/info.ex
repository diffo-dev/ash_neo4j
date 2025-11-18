# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.DataLayer.Info do
  @moduledoc "Introspection helpers for AshNeo4j.DataLayer"

  alias Spark.Dsl.Extension

  @spec domain_label(Ash.Resource.t()) :: atom() | nil
  @doc """
  The domain label is the PascalCase short name of the domain's Elixir Module name, which is used as a Neo4j label for all nodes of resources in the domain.
  """
  def domain_label(domain) do
    Extension.get_opt(domain, [:neo4j], :domain_label, nil, true)
  end

  @doc """
  The label is the PascalCase short name of the resource's Elixir Module name by default, but can be overridden by setting the :label option in the DSL. It is used as a Neo4j label for all nodes of the resource.
  """
  @spec label(Ash.Resource.t()) :: atom() | nil
  def label(resource) do
    Extension.get_opt(resource, [:neo4j], :label, nil, true)
  end

  @spec relate(Ash.Resource.t()) :: list(tuple()) | nil
  def relate(resource) do
    Extension.get_opt(resource, [:neo4j], :relate, [], true)
  end

  @spec guard(Ash.Resource.t()) :: list(tuple()) | nil
  def guard(resource) do
    Extension.get_opt(resource, [:neo4j], :guard, [], true)
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

  @spec relationship_attributes(Ash.Resource.t()) :: keyword() | nil
  def relationship_attributes(resource) do
    Extension.get_opt(resource, [:neo4j], :relationship_attributes, [], true)
  end

  @doc """
  Returns the list of labels for the resource, including the domain label and the resource label, if they exist
   The domain label is the PascalCase short name of the domain module, and the resource label is the PascalCase short name of the resource module by default, but can be overridden by setting the :label option in the DSL.
  """
  @spec labels(Ash.Resource.t()) :: list(atom()) | nil
  def labels(resource) do
    [domain_label(resource), label(resource)]
    |> Enum.uniq()
    |> Enum.filter(& &1)
  end

  @doc """
  Returns a node_relationship that matches the relationship name
  """
  @spec node_relationship(Ash.Resource.t(), atom() | String.t()) :: tuple() | nil
  def node_relationship(resource, name) when is_atom(resource) and is_atom(name) do
    List.keyfind(relate(resource), name, 0)
  end

  def node_relationship(resource, name) when is_atom(resource) and is_bitstring(name) do
    List.keyfind(relate(resource), String.to_atom(name), 0)
  end

  @doc """
  Returns a node_relationship that matches the edge label, edge direction and destination label
  """
  @spec node_relationship(Ash.Resource.t(), atom(), atom(), atom()) :: tuple() | nil
  def node_relationship(resource, edge_label, edge_direction, destination_label)
      when is_atom(resource) and is_atom(edge_label) and is_atom(edge_direction) and is_atom(destination_label) do
    Enum.find(
      relate(resource),
      fn related ->
        case related do
          {_, ^edge_label, ^edge_direction, ^destination_label} -> true
          _ -> false
        end
      end
    )
  end

  @doc """
  Returns the relationship from the source attribute, if any
  """
  @spec relationship(Ash.Resource.t(), atom() | String.t()) :: tuple() | nil
  def relationship(resource, source_attribute) when is_atom(resource) and is_atom(source_attribute) do
    List.keyfind(relationship_attributes(resource), source_attribute, 0)
  end

  def relationship(resource, source_attribute) when is_atom(resource) and is_bitstring(source_attribute) do
    List.keyfind(relationship_attributes(resource), String.to_atom(source_attribute), 0)
  end

  @doc """
  Returns a matching Ash.Resource.Info relationship given edge label, edge direction and destination node label
  """
  @spec relationship(Ash.Resource.t(), atom(), atom(), atom()) :: struct() | nil
  def relationship(resource, edge_label, edge_direction, destination_label)
      when is_atom(resource) and is_atom(edge_label) and is_atom(edge_direction) and is_atom(destination_label) do
    node_relationship = node_relationship(resource, edge_label, edge_direction, destination_label)

    if node_relationship != nil do
      Ash.Resource.Info.relationship(resource, elem(node_relationship, 0))
    end
  end

  @doc """
  Returns the reverse node relationship given resource and relationship name
  """
  @spec reverse_node_relationship(Ash.Resource.t(), atom()) :: tuple() | nil
  def reverse_node_relationship(resource, name) when is_atom(resource) and is_atom(name) do
    destination_resource = Ash.Resource.Info.related(resource, name)
    reverse_relationship_path = Ash.Resource.Info.reverse_relationship(resource, [name])

    if reverse_relationship_path != nil do
      node_relationship(destination_resource, hd(reverse_relationship_path))
    end
  end

  @doc """
  Returns the reverse relationship given resource and relationship name
  """
  @spec reverse_relationship(Ash.Resource.t(), atom()) :: tuple() | nil
  def reverse_relationship(resource, name) when is_atom(resource) and is_atom(name) do
    destination_resource = Ash.Resource.Info.related(resource, name)
    reverse_relationship_path = Ash.Resource.Info.reverse_relationship(resource, [name])

    if reverse_relationship_path != nil do
      Ash.Resource.Info.relationship(destination_resource, hd(reverse_relationship_path))
    end
  end

  @doc """
  Returns whether the relationship is exclusive on the source resource
  """
  @spec source_exclusive?(Ash.Resource.t(), atom()) :: boolean()
  def source_exclusive?(resource, name) when is_atom(resource) and is_atom(name) do
    relationship = Ash.Resource.Info.relationship(resource, name)
    relationship.cardinality == :one
  end

  @doc """
  Returns whether the relationship is exclusive on the destination resource, given a source resource and source relationship name
  """
  @spec destination_exclusive?(Ash.Resource.t(), atom()) :: boolean()
  def destination_exclusive?(resource, name) when is_atom(resource) and is_atom(name) do
    destination_resource = Ash.Resource.Info.related(resource, name)

    if resource == destination_resource do
      # same resource
      {^name, edge_label, edge_direction, destination_label} = node_relationship(resource, name)

      reverse_relationship =
        relationship(destination_resource, edge_label, reverse(edge_direction), destination_label)

      if reverse_relationship != nil do
        reverse_relationship.cardinality == :one
      else
        false
      end
    else
      # different resource
      reverse_relationship_path = Ash.Resource.Info.reverse_relationship(resource, [name])

      if reverse_relationship_path != nil do
        reverse_relationship = Ash.Resource.Info.relationship(destination_resource, hd(reverse_relationship_path))
        reverse_relationship.cardinality == :one
      else
        false
      end
    end
  end

  @doc """
  Returns the source node property name given the source resource, dest_resource and destination attribute name, i.e. post_id returns uuid
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
  def convert_to_property_name(resource, ash_query_ref)
      when is_atom(resource) and is_struct(ash_query_ref, Ash.Query.Ref) do
    attribute_name = Ash.Query.Ref.name(ash_query_ref)
    convert_to_property_name(resource, attribute_name)
  end

  @spec convert_to_property_name(Ash.Resource.t(), atom()) :: String.t() | nil
  def convert_to_property_name(resource, attribute_name) when is_atom(resource) and is_atom(attribute_name) do
    translation(resource)
    |> Keyword.get(attribute_name, attribute_name)
    |> to_string()
  end

  @doc """
  Converts attributes to node properties
  """
  @spec convert_to_properties(Ash.Resource.t(), map()) :: map()
  def convert_to_properties(resource, attributes) when is_atom(resource) and is_map(attributes) do
    translation = translation(resource)

    Enum.reduce(attributes, %{}, fn {attribute_name, value}, acc ->
      property_name = Keyword.get(translation, attribute_name, attribute_name)
      Map.put(acc, property_name, value)
    end)
  end

  @doc """
  Returns the list of node relationships which block resource deletion, given the source resource
  The node relationships are tuples of {edge_label, edge_direction, destination_label}
  These include explicit guard relationships.
  """
  @spec preserve_node_relationships(Ash.Resource.t()) :: list(tuple())
  def preserve_node_relationships(resource) when is_atom(resource) do
    Enum.reduce(relate(resource), guard(resource), fn {name, edge_label, edge_direction, destination_label}, acc ->
      relationship = Ash.Resource.Info.relationship(resource, name)
      reverse_node_relationship = reverse_node_relationship(resource, relationship.name)

      if reverse_node_relationship do
        reverse_relationship =
          Ash.Resource.Info.relationship(relationship.destination, elem(reverse_node_relationship, 0))

        cond do
          reverse_relationship && reverse_relationship.cardinality == :one ->
            if reverse_relationship.allow_nil? do
              acc
            else
              [{edge_label, edge_direction, destination_label} | acc]
            end

          true ->
            acc
        end
      else
        acc
      end
    end)
  end

  @doc """
  Returns the reverse direction
  """
  def reverse(direction) when is_atom(direction) do
    case direction do
      :incoming -> :outgoing
      :outgoing -> :incoming
      _ -> nil
    end
  end
end
