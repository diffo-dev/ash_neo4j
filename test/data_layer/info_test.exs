# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.DataLayer.InfoTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias AshNeo4j.DataLayer.Info, as: DataLayerInfo
  alias AshNeo4j.DataLayer.Domain.Info, as: DomainInfo
  alias AshNeo4j.Resource.Info, as: ResourceInfo
  alias AshNeo4j.Test.Provider
  alias AshNeo4j.Test.Resource.Blueprint
  alias AshNeo4j.Test.Resource.Specification
  alias AshNeo4j.Test.Resource.Event

  describe "datalayer info" do
    test "label" do
      refute DataLayerInfo.label(Specification)
      assert DataLayerInfo.label(Event) == :Event
    end

    test "relate" do
      assert DataLayerInfo.relate(Specification) == []

      assert DataLayerInfo.relate(Event) == [
               {:service, :RAISED, :incoming, :Service},
               {:resource, :FIRED, :incoming, :Resource}
             ]
    end

    test "guard" do
      assert DataLayerInfo.guard(Specification) == [
               {:SPECIFIES, :outgoing, :Service},
               {:SPECIFIES, :outgoing, :Resource}
             ]

      assert DataLayerInfo.guard(Event) == []
    end

    test "skip" do
      assert DataLayerInfo.skip(Specification) == []
      assert DataLayerInfo.skip(Event) == [:service_id, :resource_id]
    end
  end

  describe "domain info" do
    test "label returns nil for domains without AshNeo4j.DataLayer.Domain" do
      assert DomainInfo.label(AshNeo4j.Test.SRM) == nil
    end

    test "label returns the declared label for a domain using a domain fragment" do
      assert DomainInfo.label(Provider) == :MyTestDomain
    end
  end

  describe "resource info — domain fragment label" do
    test "domain_fragment_label is nil for resources in a plain domain" do
      assert ResourceInfo.domain_fragment_label(Specification) == nil
    end

    test "domain_fragment_label is populated for resources in a domain with a domain fragment" do
      assert ResourceInfo.domain_fragment_label(Blueprint) == :MyTestDomain
    end

    test "all_labels includes domain fragment label when domain fragment is present" do
      assert ResourceInfo.all_labels(Blueprint) == [:Provider, :Blueprint, :MyTestDomain]
    end

    test "mapping includes domain_fragment_label field" do
      mapping = ResourceInfo.mapping(Blueprint)
      assert mapping.domain_fragment_label == :MyTestDomain
      assert :MyTestDomain in mapping.all_labels
    end
  end
end
