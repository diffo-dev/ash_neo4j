# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Resource.Info do
  @moduledoc "Resource information for AshNeo4j.DataLayer"

  alias Spark.Dsl.Extension
  alias AshNeo4j.Util

  @doc """
  The resource label if set via the DSL, or defaulted as the PascalCase short name of the resource's Elixir Module name. It is used on all operations.
  """
  @spec label(Ash.Resource.t()) :: atom() | nil
  def label(resource) do
    Extension.get_persisted(resource, :label, nil)
  end

  @doc """
  The domain label is the PascalCase short name of the domain's Elixir Module name. It is used only on create.
  """
  @spec domain_label(Ash.Resource.t()) :: atom() | nil
  def domain_label(resource) do
    Extension.get_persisted(resource, :domain_label, nil)
  end

  @doc """
  Returns the list of labels for the resource. This will consist of any domain label then resource label.
  """
  @spec labels(Ash.Resource.t()) :: list(atom()) | nil
  def labels(resource) do
    [domain_label(resource), label(resource)]
    |> Enum.uniq()
    |> Enum.filter(& &1)
  end

  @doc """
  Returns the effective relate of the resource, merging DSL and defaults
  """
  @spec relate(Ash.Resource.t()) :: list(tuple()) | nil
  def relate(resource) do
    Extension.get_persisted(resource, :relate, [])
  end

  @doc """
  Returns the list of attribute translations for the resource.
  """
  @spec translations(Ash.Resource.t()) :: keyword() | nil
  def translations(resource) do
    Extension.get_persisted(resource, :translations, [])
  end

  @doc """
  Returns the relationship attributes for the resource.
  """
  @spec relationship_attributes(Ash.Resource.t()) :: keyword() | nil
  def relationship_attributes(resource) do
    Extension.get_persisted(resource, :relationship_attributes, [])
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

  @spec node_relationship(Ash.Resource.t(), atom(), atom(), list(atom())) :: tuple() | nil
  def node_relationship(resource, edge_label, edge_direction, destination_labels)
      when is_atom(resource) and is_atom(edge_label) and is_atom(edge_direction) and is_list(destination_labels) do
    destination_labels = List.delete(destination_labels, domain_label(resource))

    Enum.reduce_while(destination_labels, nil, fn destination_label, acc ->
      node_relationship =
        Enum.find(
          relate(resource),
          fn related ->
            case related do
              {_, ^edge_label, ^edge_direction, ^destination_label} -> true
              _ -> false
            end
          end
        )

      if node_relationship do
        {:halt, node_relationship}
      else
        {:cont, acc}
      end
    end)
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

  @spec relationship(Ash.Resource.t(), atom(), atom(), list(atom())) :: struct() | nil
  def relationship(resource, edge_label, edge_direction, destination_labels)
      when is_atom(resource) and is_atom(edge_label) and is_atom(edge_direction) and is_list(destination_labels) do
    node_relationship = node_relationship(resource, edge_label, edge_direction, destination_labels)

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
        relationship(destination_resource, edge_label, Util.reverse(edge_direction), destination_label)

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

    translations(source_resource)
    |> Keyword.get(attribute_name, attribute_name)
  end

  @doc """
  Converts an attribute name to a node property name string, translating if necessary
  The attribute name can be an Ash.Query.Ref or atom
  """
  @spec convert_to_property_name(Ash.Resource.t(), Ash.Query.Ref.t()) :: String.t() | nil
  def convert_to_property_name(resource, ash_query_ref)
      when is_atom(resource) and is_struct(ash_query_ref, Ash.Query.Ref) do
    attribute_name = Ash.Query.Ref.name(ash_query_ref)
    convert_to_property_name(resource, attribute_name)
  end

  @spec convert_to_property_name(Ash.Resource.t(), atom()) :: String.t() | nil
  def convert_to_property_name(resource, attribute_name) when is_atom(resource) and is_atom(attribute_name) do
    translations(resource)
    |> Keyword.get(attribute_name, attribute_name)
    |> to_string()
  end

  @doc """
  Returns the Ash.Type of the attribute from the name
  """
  @spec attribute_type(Ash.Resource.t(), atom()) :: Ash.Type.t() | nil
  def attribute_type(resource, ash_query_ref) when is_atom(resource) and is_struct(ash_query_ref, Ash.Query.Ref) do
    attribute_name = Ash.Query.Ref.name(ash_query_ref)
    attribute_type(resource, attribute_name)
  end

  @spec attribute_type(Ash.Resource.t(), atom()) :: Ash.Type.t() | nil
  def attribute_type(resource, attribute_name) when is_atom(resource) and is_atom(attribute_name) do
    case Ash.Resource.Info.attribute(resource, attribute_name) do
      nil -> nil
      attribute -> attribute.type
    end
  end

  @doc """
  Converts attributes to node properties
  """
  @spec convert_to_properties(Ash.Resource.t(), map()) :: map()
  def convert_to_properties(resource, attributes) when is_atom(resource) and is_map(attributes) do
    translations = translations(resource)

    Enum.reduce(attributes, %{}, fn {attribute_name, value}, acc ->
      property_name = Keyword.get(translations, attribute_name, attribute_name)
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
    Enum.reduce(relate(resource), AshNeo4j.DataLayer.Info.guard(resource), fn {name, edge_label, edge_direction,
                                                                               destination_label},
                                                                              acc ->
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
end
