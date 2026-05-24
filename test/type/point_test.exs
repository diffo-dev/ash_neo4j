# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Type.PointTest do
  @moduledoc """
  End-to-end round-trip of AshNeo4j.Type.Point through the data layer:
  Ash.create! → Neo4j → Ash.get! preserves the Bolty.Types.Point struct.
  """
  use ExUnit.Case, async: true

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Place
  alias Bolty.Types.Point

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  describe "round-trip through the data layer" do
    test "WGS-84 2D Point survives create + read" do
      sydney = Point.create(:wgs_84, 151.2093, -33.8688)

      created = Place |> Ash.create!(%{name: "Sydney CBD", location: sydney})
      assert created.location == sydney

      reloaded = Place |> Ash.get!(created.id)
      assert reloaded.location == sydney
    end

    test "nil location is preserved" do
      created = Place |> Ash.create!(%{name: "No location"})
      assert created.location == nil

      reloaded = Place |> Ash.get!(created.id)
      assert reloaded.location == nil
    end
  end

  describe "cast_input validation" do
    test "rejects non-WGS-84 srid with a clear error" do
      cartesian = Point.create(:cartesian, 10.0, 20.0)

      assert {:error, _} =
               Place
               |> Ash.Changeset.for_create(:create, %{name: "Bad CRS", location: cartesian})
               |> Ash.create()
    end

    test "rejects non-Point input with a clear error" do
      assert {:error, _} =
               Place
               |> Ash.Changeset.for_create(:create, %{name: "Bad type", location: %{lng: 1, lat: 2}})
               |> Ash.create()
    end
  end
end
