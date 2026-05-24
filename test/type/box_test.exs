# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Type.BoxTest do
  @moduledoc """
  End-to-end round-trip of AshNeo4j.Type.Box through the data layer.
  """
  use ExUnit.Case, async: true

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Place
  alias AshNeo4j.Type.Box
  alias Bolty.Types.Point

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  defp sydney_box do
    %Box{
      sw: Point.create(:wgs_84, 151.0, -34.0),
      ne: Point.create(:wgs_84, 151.5, -33.5)
    }
  end

  describe "round-trip through the data layer" do
    test "WGS-84 2D Box survives create + read" do
      box = sydney_box()

      created = Place |> Ash.create!(%{name: "Sydney bbox", bounds: box})
      assert created.bounds == box

      reloaded = Place |> Ash.get!(created.id)
      assert reloaded.bounds == box
    end

    test "nil bounds is preserved" do
      created = Place |> Ash.create!(%{name: "No bbox"})
      assert created.bounds == nil

      reloaded = Place |> Ash.get!(created.id)
      assert reloaded.bounds == nil
    end
  end

  describe "cast_input validation" do
    test "rejects non-WGS-84 sw corner" do
      bad = %Box{sw: Point.create(:cartesian, 0.0, 0.0), ne: Point.create(:wgs_84, 1.0, 1.0)}

      assert {:error, _} =
               Place
               |> Ash.Changeset.for_create(:create, %{name: "Bad sw CRS", bounds: bad})
               |> Ash.create()
    end

    test "rejects sw.x > ne.x (antimeridian-like)" do
      bad = %Box{sw: Point.create(:wgs_84, 151.5, -34.0), ne: Point.create(:wgs_84, 151.0, -33.5)}

      assert {:error, _} =
               Place
               |> Ash.Changeset.for_create(:create, %{name: "Reversed lng", bounds: bad})
               |> Ash.create()
    end

    test "rejects sw.y > ne.y (latitude inverted)" do
      bad = %Box{sw: Point.create(:wgs_84, 151.0, -33.5), ne: Point.create(:wgs_84, 151.5, -34.0)}

      assert {:error, _} =
               Place
               |> Ash.Changeset.for_create(:create, %{name: "Reversed lat", bounds: bad})
               |> Ash.create()
    end

    test "rejects non-Box input" do
      assert {:error, _} =
               Place
               |> Ash.Changeset.for_create(:create, %{name: "Bad type", bounds: %{sw: 1, ne: 2}})
               |> Ash.create()
    end
  end
end
