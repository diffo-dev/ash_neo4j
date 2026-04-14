# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Info do
  @moduledoc false
  use ExUnit.Case
  alias AshNeo4j.DataLayer.Info
  alias AshNeo4j.Test.Resource.Specification
  alias AshNeo4j.Test.Resource.Event

  describe "datalayer info" do
    test "label" do
      assert Info.label(Specification) == :Specification
    end

    test "domain_label" do
      assert Info.domain_label(Specification) == :Srm
    end

    test "labels" do
      assert Info.labels(Specification) == [:Srm, :Specification]
    end

    test "relate" do
      assert Info.relate(Event) == [
      {:service, :RAISED, :incoming, :Service},
      {:resource, :FIRED, :incoming, :Resource}
    ]
    end

    test "guard" do
      assert Info.guard(Specification) == [
               {:SPECIFIES, :outgoing, :Service},
               {:SPECIFIES, :outgoing, :Resource}
             ]
    end

    test "skip" do
      assert Info.skip(Event) == [:service_id, :resource_id]
    end

    test "translations" do
      assert Info.translations(Specification) == [
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

    test "relationship attributes" do
      assert Info.relationship_attributes(Event) == [{:service_id, :service}, {:resource_id, :resource}]
    end
  end
end
