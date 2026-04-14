# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Resource.InfoTest do
  @moduledoc false
  use ExUnit.Case
  alias AshNeo4j.Resource.Info, as: ResourceInfo
  alias AshNeo4j.Test.Resource.Event

  alias AshNeo4j.Test.Resource.Resource

  alias AshNeo4j.Test.Resource.Service
  alias AshNeo4j.Test.Resource.Specification

  describe "label" do
    test "explicit label is returned" do
      assert ResourceInfo.label(Event) == :Event
    end

    test "defaulted label is the module short name" do
      # Specification has no explicit label in neo4j do block
      assert ResourceInfo.label(Specification) == :Specification
    end
  end

  describe "domain_label" do
    test "domain label is derived from domain module short name" do
      assert ResourceInfo.domain_label(Specification) == :Srm
      assert ResourceInfo.domain_label(Service) == :Srm
      assert ResourceInfo.domain_label(Event) == :Srm
    end
  end

  describe "labels" do
    test "returns domain label then resource label" do
      assert ResourceInfo.labels(Specification) == [:Srm, :Specification]
      assert ResourceInfo.labels(Service) == [:Srm, :Service]
      assert ResourceInfo.labels(Event) == [:Srm, :Event]
    end
  end

  describe "relate" do
    test "returns empty list when no relationships declared" do
      # Specification has no Ash relationships - the graph would be too dense.
      # Guards handle deletion protection via the neo4j DSL instead.
      assert ResourceInfo.relate(Specification) == []
    end

    test "returns explicit user-declared relate entries for Event" do
      assert ResourceInfo.relate(Event) == [
               {:service, :RAISED, :incoming, :Service},
               {:resource, :FIRED, :incoming, :Resource}
             ]
    end

    test "returns all relate entries for Service including self-referential" do
      relate = ResourceInfo.relate(Service)
      assert {:specification, :SPECIFIES, :incoming, :Specification} in relate
      assert {:parent_service, :MANAGES, :incoming, :Service} in relate
      assert {:services, :MANAGES, :outgoing, :Service} in relate
      assert {:resources, :CONFIGURES, :outgoing, :Resource} in relate
      assert {:event, :RAISED, :outgoing, :Event} in relate
    end
  end

  describe "translations" do
    test "id is translated using type short name" do
      assert Keyword.get(ResourceInfo.translations(Specification), :id) == :uuid
      assert Keyword.get(ResourceInfo.translations(Event), :id) == :uuid
    end

    test "attributes with explicit source use the source" do
      translations = ResourceInfo.translations(Specification)
      assert Keyword.get(translations, :major_version) == :versionMajor
      assert Keyword.get(translations, :minor_version) == :versionMinor
      assert Keyword.get(translations, :patch_version) == :versionPatch
      assert Keyword.get(translations, :tmf_version) == :tmfVersion
    end

    test "attributes without source are camelCased" do
      translations = ResourceInfo.translations(Event)
      assert Keyword.get(translations, :inserted_at) == :insertedAt
      assert Keyword.get(translations, :updated_at) == :updatedAt
    end

    test "belongs_to source attributes are excluded from translations" do
      # service_id and resource_id are belongs_to source attributes, skipped
      translations = ResourceInfo.translations(Event)
      refute Keyword.has_key?(translations, :service_id)
      refute Keyword.has_key?(translations, :resource_id)
    end

    test "full translation map for Specification" do
      assert ResourceInfo.translations(Specification) == [
               {:id, :uuid},
               {:href, :href},
               {:name, :name},
               {:type, :type},
               {:major_version, :versionMajor},
               {:minor_version, :versionMinor},
               {:patch_version, :versionPatch},
               {:tmf_version, :tmfVersion}
             ]
    end

    test "full translation map for Event" do
      assert ResourceInfo.translations(Event) == [
               {:id, :uuid},
               {:type, :type},
               {:inserted_at, :insertedAt},
               {:updated_at, :updatedAt}
             ]
    end
  end

  describe "relationship_attributes" do
    test "returns empty list for resource with no belongs_to" do
      assert ResourceInfo.relationship_attributes(Specification) == []
    end

    test "returns source_attribute to relationship name pairs for belongs_to" do
      rel_attrs = ResourceInfo.relationship_attributes(Event)
      assert {:service_id, :service} in rel_attrs
      assert {:resource_id, :resource} in rel_attrs
    end
  end

  describe "node_relationship/2 - by name" do
    test "returns the matching relate tuple by relationship name atom" do
      assert ResourceInfo.node_relationship(Event, :service) ==
               {:service, :RAISED, :incoming, :Service}

      assert ResourceInfo.node_relationship(Event, :resource) ==
               {:resource, :FIRED, :incoming, :Resource}
    end

    test "returns the matching relate tuple by relationship name string" do
      assert ResourceInfo.node_relationship(Event, "service") ==
               {:service, :RAISED, :incoming, :Service}
    end

    test "returns self-referential relate tuples" do
      assert ResourceInfo.node_relationship(Service, :parent_service) ==
               {:parent_service, :MANAGES, :incoming, :Service}

      assert ResourceInfo.node_relationship(Service, :services) ==
               {:services, :MANAGES, :outgoing, :Service}
    end

    test "returns nil when relationship name not found" do
      assert ResourceInfo.node_relationship(Event, :nonexistent) == nil
    end

    test "returns nil for resource with no relate" do
      assert ResourceInfo.node_relationship(Specification, :anything) == nil
    end
  end

  describe "node_relationship/4 - by edge label, direction, destination atom" do
    test "returns matching relate tuple" do
      assert ResourceInfo.node_relationship(Event, :RAISED, :incoming, :Service) ==
               {:service, :RAISED, :incoming, :Service}

      assert ResourceInfo.node_relationship(Service, :RAISED, :outgoing, :Event) ==
               {:event, :RAISED, :outgoing, :Event}
    end

    test "returns nil when direction does not match" do
      assert ResourceInfo.node_relationship(Event, :RAISED, :outgoing, :Service) == nil
    end

    test "returns nil when edge label does not match" do
      assert ResourceInfo.node_relationship(Event, :FIRED, :incoming, :Service) == nil
    end
  end

  describe "node_relationship/4 - by edge label, direction, destination labels list" do
    test "matches when destination label is in list" do
      assert ResourceInfo.node_relationship(Event, :RAISED, :incoming, [:Srm, :Service]) ==
               {:service, :RAISED, :incoming, :Service}
    end

    test "strips domain label from list before matching" do
      # :Srm is domain label and must be excluded before lookup
      assert ResourceInfo.node_relationship(Event, :RAISED, :incoming, [:Srm, :Service]) ==
               ResourceInfo.node_relationship(Event, :RAISED, :incoming, :Service)
    end

    test "returns nil when only domain label remains after stripping" do
      assert ResourceInfo.node_relationship(Event, :RAISED, :incoming, [:Srm]) == nil
    end

    test "returns nil when no label in list matches" do
      assert ResourceInfo.node_relationship(Event, :RAISED, :incoming, [:Srm, :Resource]) == nil
    end
  end

  describe "relationship/2 - by source attribute" do
    test "returns relationship tuple for a known source attribute atom" do
      assert ResourceInfo.relationship(Event, :service_id) == {:service_id, :service}
      assert ResourceInfo.relationship(Event, :resource_id) == {:resource_id, :resource}
    end

    test "returns relationship tuple for a known source attribute string" do
      assert ResourceInfo.relationship(Event, "service_id") == {:service_id, :service}
    end

    test "returns nil for unknown source attribute" do
      assert ResourceInfo.relationship(Event, :nonexistent_id) == nil
    end

    test "returns nil for resource with no relationship attributes" do
      assert ResourceInfo.relationship(Specification, :anything) == nil
    end
  end

  describe "relationship/4 - by edge label, direction, destination" do
    test "returns Ash relationship struct matching edge label, direction, destination atom" do
      rel = ResourceInfo.relationship(Event, :RAISED, :incoming, :Service)
      assert rel != nil
      assert rel.name == :service
      assert rel.type == :belongs_to
      assert rel.destination == AshNeo4j.Test.Resource.Service
    end

    test "returns Ash relationship struct matching edge label, direction, destination list" do
      rel = ResourceInfo.relationship(Event, :RAISED, :incoming, [:Srm, :Service])
      assert rel != nil
      assert rel.name == :service
      assert rel.destination == AshNeo4j.Test.Resource.Service
    end

    test "returns nil when no match" do
      assert ResourceInfo.relationship(Event, :RAISED, :outgoing, :Service) == nil
    end
  end

  describe "reverse_node_relationship" do
    test "returns the reverse node relationship for the has_one side" do
      # Service relate has {:event, :RAISED, :outgoing, :Event}
      # Event relate has {:service, :RAISED, :incoming, :Service} — same edge, flipped direction
      assert ResourceInfo.reverse_node_relationship(Service, :event) ==
               {:service, :RAISED, :incoming, :Service}
    end

    test "returns the reverse node relationship for the belongs_to side" do
      # Event belongs_to :service, reverse is Service has_one :event
      assert ResourceInfo.reverse_node_relationship(Event, :service) ==
               {:event, :RAISED, :outgoing, :Event}
    end

    test "returns nil for Specification since no Ash relationships declared" do
      # Specification deliberately has no Ash relationships — graph would be too dense.
      # Guards handle deletion protection without full relationship traversal.
      assert ResourceInfo.reverse_node_relationship(Specification, :service) == nil
    end
  end

  describe "reverse_relationship" do
    test "returns the Ash reverse relationship for the has_one side" do
      reverse = ResourceInfo.reverse_relationship(Service, :event)
      assert reverse != nil
      assert reverse.name == :service
      assert reverse.type == :belongs_to
      assert reverse.destination == AshNeo4j.Test.Resource.Service
    end

    test "returns the Ash reverse relationship for the belongs_to side" do
      reverse = ResourceInfo.reverse_relationship(Event, :service)
      assert reverse != nil
      assert reverse.name == :event
      assert reverse.type == :has_one
      assert reverse.destination == AshNeo4j.Test.Resource.Event
    end

    test "returns nil for Specification since no Ash relationships declared" do
      assert ResourceInfo.reverse_relationship(Specification, :service) == nil
    end
  end

  describe "source_exclusive?" do
    test "returns true for belongs_to (cardinality :one)" do
      assert ResourceInfo.source_exclusive?(Event, :service) == true
      assert ResourceInfo.source_exclusive?(Event, :resource) == true
    end

    test "returns true for has_one (cardinality :one)" do
      assert ResourceInfo.source_exclusive?(Service, :event) == true
    end

    test "returns false for has_many (cardinality :many)" do
      assert ResourceInfo.source_exclusive?(Service, :services) == false
      assert ResourceInfo.source_exclusive?(Service, :resources) == false
    end
  end

  describe "destination_exclusive?" do
    test "returns true when reverse relationship has cardinality :one" do
      # Service has_one :event — a Service can only have one Event
      assert ResourceInfo.destination_exclusive?(Event, :service) == true
    end

    test "returns false when reverse relationship has cardinality :many" do
      # Service has_many :resources — a Service can have many Resources
      assert ResourceInfo.destination_exclusive?(Resource, :service) == false
    end
  end

  describe "convert_to_property_name" do
    test "returns camelCase string for a translated attribute" do
      assert ResourceInfo.convert_to_property_name(Specification, :major_version) == "versionMajor"
      assert ResourceInfo.convert_to_property_name(Event, :inserted_at) == "insertedAt"
    end

    test "returns attribute name as string when no translation defined" do
      assert ResourceInfo.convert_to_property_name(Specification, :name) == "name"
    end

    test "returns id translation" do
      assert ResourceInfo.convert_to_property_name(Specification, :id) == "uuid"
      assert ResourceInfo.convert_to_property_name(Event, :id) == "uuid"
    end
  end

  describe "convert_to_properties" do
    test "converts attribute map keys using translations" do
      attrs = %{major_version: 1, minor_version: 0, name: "test"}
      props = ResourceInfo.convert_to_properties(Specification, attrs)
      assert Map.get(props, :versionMajor) == 1
      assert Map.get(props, :versionMinor) == 0
      assert Map.get(props, :name) == "test"
    end

    test "returns empty map for empty attributes" do
      assert ResourceInfo.convert_to_properties(Specification, %{}) == %{}
    end
  end

  describe "attribute_type" do
    test "returns nil for unknown attribute" do
      assert ResourceInfo.attribute_type(Specification, :nonexistent) == nil
      assert ResourceInfo.attribute_type(Event, :nonexistent) == nil
    end
  end

  describe "preserve_node_relationships" do
    # Specification is guarded against deletion when Services or Resources still
    # reference it via SPECIFIES edges — you must not delete a Specification while
    # Services depend on it.
    # belongs_to allow_nil? defaults to true in Ash, so reverse belongs_to relationships
    # do not block deletion. Only explicit guards and non-nil reverse :one relationships do.

    test "returns guard list for Specification since relate is empty" do
      assert ResourceInfo.preserve_node_relationships(Specification) == [
               {:SPECIFIES, :outgoing, :Service},
               {:SPECIFIES, :outgoing, :Resource}
             ]
    end

    test "returns empty list for Service since no guard and all reverse belongs_to are allow_nil?: true" do
      assert ResourceInfo.preserve_node_relationships(Service) == []
    end

    test "returns empty list for Event since no guard and no blocking reverses" do
      assert ResourceInfo.preserve_node_relationships(Event) == []
    end
  end
end
