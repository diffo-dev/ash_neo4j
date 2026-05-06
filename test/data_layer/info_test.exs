# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.DataLayer.InfoTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias AshNeo4j.DataLayer.Info, as: DataLayerInfo
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
end
