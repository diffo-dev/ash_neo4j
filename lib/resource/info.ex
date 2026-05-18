# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Resource.Info do
  @moduledoc "Resource information for AshNeo4j.DataLayer"

  alias Spark.Dsl.Extension
  alias AshNeo4j.Util
  alias AshNeo4j.{EdgeDescriptor, ResourceMapping}

  @doc """
  The match label used for read, update, and destroy operations. This is the value of `label` in
  the `neo4j do` block — which may come from a fragment (e.g. `:Instance` from `BaseInstance`).
  Defaults to the PascalCase short name of the resource module.
  """
  @spec label(Ash.Resource.t()) :: atom() | nil
  def label(resource) do
    Extension.get_persisted(resource, :label, nil)
  end

  @doc """
  The label derived from the resource module's own short name (e.g. `:Shelf` for
  `MyApp.Access.Shelf`). Always set regardless of any fragment label override.
  Use this when you need to identify the specific resource type rather than its base type.
  """
  @spec module_label(Ash.Resource.t()) :: atom() | nil
  def module_label(resource) do
    Extension.get_persisted(resource, :module_label, nil)
  end

  @doc """
  The domain label is the PascalCase short name of the domain's Elixir Module name. It is used only on create.
  """
  @spec domain_label(Ash.Resource.t()) :: atom() | nil
  def domain_label(resource) do
    Extension.get_persisted(resource, :domain_label, nil)
  end

  @doc """
  The label contributed by a domain fragment using `AshNeo4j.DataLayer.Domain`.
  Written on CREATE as an additional label for graph traversal. `nil` when the domain
  declares no fragment label.
  """
  @spec domain_fragment_label(Ash.Resource.t()) :: atom() | nil
  def domain_fragment_label(resource) do
    case Extension.get_persisted(resource, :domain_fragment_label, nil) do
      nil ->
        domain = Extension.get_persisted(resource, :domain, nil)
        if domain, do: AshNeo4j.DataLayer.Domain.Info.label(domain), else: nil

      val ->
        val
    end
  end

  @doc """
  The two-label pair `[domain_label, module_label]` used in MATCH for all read, update,
  delete, and aggregate operations. Always uniquely identifies this specific resource type.
  """
  @spec label_pair(Ash.Resource.t()) :: [atom()]
  def label_pair(resource) do
    Extension.get_persisted(resource, :label_pair, [domain_label(resource), module_label(resource)])
  end

  @doc """
  Returns the full list of labels written to the node on CREATE. Always starts with the domain
  label, followed by the module label, then any additional base type label from a resource
  fragment, then the domain fragment label if the domain uses `AshNeo4j.DataLayer.Domain`.
  For example, `DiffoExample.Access.Shelf` (using `BaseInstance` and a `Telco` domain fragment)
  returns `[:Access, :Shelf, :Instance, :Telco]`.
  """
  @spec all_labels(Ash.Resource.t()) :: list(atom()) | nil
  def all_labels(resource) do
    Extension.get_persisted(resource, :all_labels, nil) ||
      [domain_label(resource), module_label(resource), label(resource), domain_fragment_label(resource)]
      |> Enum.uniq()
      |> Enum.filter(& &1)
  end

  @doc """
  Returns the complete graph mapping for a resource as a `%AshNeo4j.ResourceMapping{}` struct.
  This is the single source of truth for how an Ash resource maps to the Neo4j graph.
  """
  @spec mapping(Ash.Resource.t()) :: ResourceMapping.t()
  def mapping(resource) do
    base =
      if function_exported?(resource, :__ash_neo4j_mapping__, 0) do
        resource.__ash_neo4j_mapping__()
      else
        %ResourceMapping{
          module: resource,
          domain_label: domain_label(resource),
          module_label: module_label(resource),
          label: label(resource),
          label_pair: label_pair(resource),
          properties: translations(resource),
          edges: Enum.map(relate(resource), &EdgeDescriptor.from_relate/1),
          relationship_attributes: relationship_attributes(resource),
          guards: AshNeo4j.DataLayer.Info.guard(resource),
          skip: AshNeo4j.DataLayer.Info.skip(resource)
        }
      end

    frag_label = domain_fragment_label(resource)

    %{base | domain_fragment_label: frag_label, all_labels: all_labels_for(base, frag_label)}
  end

  defp all_labels_for(%ResourceMapping{} = base, frag_label) do
    [base.domain_label, base.module_label, base.label, frag_label]
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
  Converts an attribute name to a node property name string, translating if necessary
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
