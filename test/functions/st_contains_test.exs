# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.StContainsTest do
  @moduledoc """
  End-to-end test of `st_contains(box, point)` as an Ash query expression,
  with pushdown to Neo4j's native `point.withinBBox`.
  """
  use ExUnit.Case, async: true

  require Ash.Query

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Functions.StContains
  alias AshNeo4j.Test.Resource.Place
  alias AshNeo4j.Type.Box
  alias AshNeo4j.Type.MultiBox
  alias AshNeo4j.Type.MultiPoint
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

  describe "st_contains in Ash.Query.filter" do
    setup do
      sydney = Place |> Ash.create!(%{name: "Sydney bbox", bounds: sydney_box()})
      perth = Place |> Ash.create!(%{name: "Perth bbox", bounds: %Box{
        sw: Point.create(:wgs_84, 115.5, -32.5),
        ne: Point.create(:wgs_84, 116.5, -31.5)
      }})

      {:ok, sydney: sydney, perth: perth}
    end

    test "returns places whose bounds contain the test point", %{sydney: sydney} do
      inside_sydney = Point.create(:wgs_84, 151.2, -33.8)

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_contains(bounds, ^inside_sydney))
        |> Ash.read()

      ids = Enum.map(results, & &1.id)
      assert sydney.id in ids
    end

    test "excludes places whose bounds do not contain the test point", %{sydney: sydney, perth: perth} do
      inside_sydney = Point.create(:wgs_84, 151.2, -33.8)

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_contains(bounds, ^inside_sydney))
        |> Ash.read()

      ids = Enum.map(results, & &1.id)
      assert sydney.id in ids
      refute perth.id in ids
    end

    test "returns no results when the test point is outside all boxes" do
      middle_of_australia = Point.create(:wgs_84, 134.0, -25.0)

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_contains(bounds, ^middle_of_australia))
        |> Ash.read()

      assert results == []
    end
  end

  describe "st_contains box-box (pushed down as 2 ANDed point.withinBBox)" do
    setup do
      sydney = Place |> Ash.create!(%{name: "Sydney bbox", bounds: sydney_box()})
      {:ok, sydney: sydney}
    end

    test "matches when the inner box is fully inside the place's bounds", %{sydney: sydney} do
      inner = %Box{
        sw: Point.create(:wgs_84, 151.1, -33.9),
        ne: Point.create(:wgs_84, 151.4, -33.6)
      }

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_contains(bounds, ^inner))
        |> Ash.read()

      ids = Enum.map(results, & &1.id)
      assert sydney.id in ids
    end

    test "matches when the inner box equals the place's bounds (inclusive)", %{sydney: sydney} do
      same = sydney_box()

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_contains(bounds, ^same))
        |> Ash.read()

      ids = Enum.map(results, & &1.id)
      assert sydney.id in ids
    end

    test "rejects when the inner box extends beyond the place's bounds" do
      bigger = %Box{
        sw: Point.create(:wgs_84, 150.0, -34.5),
        ne: Point.create(:wgs_84, 152.0, -33.0)
      }

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_contains(bounds, ^bigger))
        |> Ash.read()

      assert results == []
    end

    test "rejects when the inner box partially overlaps the place's bounds" do
      overlap = %Box{
        sw: Point.create(:wgs_84, 151.3, -33.8),
        ne: Point.create(:wgs_84, 151.7, -33.4)
      }

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_contains(bounds, ^overlap))
        |> Ash.read()

      assert results == []
    end
  end

  describe "st_contains(box, multipoint) — all-of semantics" do
    test "true when every point of the MultiPoint is inside the Box" do
      inside_sydney = %MultiPoint{points: [
        Point.create(:wgs_84, 151.10, -33.80),
        Point.create(:wgs_84, 151.40, -33.60)
      ]}

      assert {:known, true} = StContains.evaluate(%{arguments: [sydney_box(), inside_sydney]})
    end

    test "false when any point of the MultiPoint is outside the Box" do
      mixed = %MultiPoint{points: [
        Point.create(:wgs_84, 151.10, -33.80),
        Point.create(:wgs_84, 115.86, -31.95)
      ]}

      assert {:known, false} = StContains.evaluate(%{arguments: [sydney_box(), mixed]})
    end
  end

  describe "st_contains(multibox, point) — any-of semantics" do
    setup do
      service_area = %MultiBox{boxes: [
        %Box{sw: Point.create(:wgs_84, 151.0, -34.0), ne: Point.create(:wgs_84, 151.5, -33.5)},
        %Box{sw: Point.create(:wgs_84, 151.6, -33.4), ne: Point.create(:wgs_84, 152.0, -33.0)}
      ]}

      {:ok, service_area: service_area}
    end

    test "true when the point falls in any constituent box", %{service_area: sa} do
      in_first = Point.create(:wgs_84, 151.2, -33.8)
      assert {:known, true} = StContains.evaluate(%{arguments: [sa, in_first]})

      in_second = Point.create(:wgs_84, 151.8, -33.2)
      assert {:known, true} = StContains.evaluate(%{arguments: [sa, in_second]})
    end

    test "false when the point falls in none of the boxes", %{service_area: sa} do
      gap = Point.create(:wgs_84, 151.55, -33.45)
      assert {:known, false} = StContains.evaluate(%{arguments: [sa, gap]})
    end

    test "round-trips through Ash storage and pushes through in-memory filter", %{service_area: sa} do
      created = Place |> Ash.create!(%{name: "SA covering Sydney", regions: sa})
      reread = Place |> Ash.get!(created.id)

      assert %MultiBox{boxes: [b0, b1]} = reread.regions
      assert b0.sw.x == 151.0
      assert b1.ne.y == -33.0

      in_first = Point.create(:wgs_84, 151.2, -33.8)

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_contains(regions, ^in_first))
        |> Ash.read()

      assert created.id in Enum.map(results, & &1.id)
    end
  end
end
