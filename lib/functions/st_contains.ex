# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.StContains do
  @moduledoc """
  Spatial containment — true if the first geometry contains the second.

      Place
      |> Ash.Query.filter(st_contains(bounds, ^test_point))
      |> Ash.read!()

  v1 supports (post #274 rearchitecture):

  - `st_contains(%Geo.Polygon{}, %Geo.Point{})` — bbox containment.
    For axis-aligned polygons this is exact; for general polygons it's
    an over-approximation pending true point-in-polygon refinement
    (#267).
  - `st_contains(%Geo.Polygon{}, %Geo.Polygon{})` — bbox containment.
  - `st_contains(%Geo.Polygon{}, %Geo.MultiPoint{})` — all-of: every
    point of the MultiPoint must lie inside the Polygon's bbox.
  - `st_contains(%Geo.MultiPolygon{}, %Geo.Point{})` — any-of: the
    point falls in any constituent polygon's bbox.
  - `st_contains(%Geo.MultiPolygon{}, %Geo.Polygon{})` — any-of.
  - `st_contains(%Geo.MultiPolygon{}, %Geo.MultiPoint{})` — every
    point covered by some constituent polygon's bbox.

  Pushdown to Neo4j's native `point.withinBBox` happens at the
  query_helper level when the attribute is a `geo_types: [:polygon]`
  Polygon and the test value is a Point (or another Polygon for the
  ANDed-corners pattern).

  Named after the OGC / PostGIS convention (`ST_Contains`) for
  consistency with ash_geo / `AshGeo.Postgis` so consumer code reads
  the same across data layers.
  """
  use Ash.Query.Function, name: :st_contains, predicate?: true

  def args, do: [[:any, :any]]

  def returns, do: [:boolean]

  def evaluate(%{arguments: [nil, _]}), do: {:known, false}
  def evaluate(%{arguments: [_, nil]}), do: {:known, false}

  def evaluate(%{arguments: [%Geo.Polygon{} = poly, %Geo.Point{} = p]}) do
    {:known, bbox_contains_point?(poly, p)}
  end

  def evaluate(%{arguments: [%Geo.Polygon{} = outer, %Geo.Polygon{} = inner]}) do
    {:known, bbox_contains_bbox?(outer, inner)}
  end

  def evaluate(%{arguments: [%Geo.Polygon{} = poly, %Geo.MultiPoint{coordinates: pts}]}) do
    {:known, Enum.all?(pts, &bbox_contains_xy?(poly, &1))}
  end

  def evaluate(%{arguments: [%Geo.MultiPolygon{} = mpoly, %Geo.Point{} = p]}) do
    {:known, Enum.any?(polygons(mpoly), &bbox_contains_point?(&1, p))}
  end

  def evaluate(%{arguments: [%Geo.MultiPolygon{} = mpoly, %Geo.Polygon{} = inner]}) do
    {:known, Enum.any?(polygons(mpoly), &bbox_contains_bbox?(&1, inner))}
  end

  def evaluate(%{arguments: [%Geo.MultiPolygon{} = mpoly, %Geo.MultiPoint{coordinates: pts}]}) do
    {:known, Enum.all?(pts, fn p -> Enum.any?(polygons(mpoly), &bbox_contains_xy?(&1, p)) end)}
  end

  def evaluate(_), do: :unknown

  defp bbox_contains_point?(%Geo.Polygon{} = poly, %Geo.Point{coordinates: {x, y}}) do
    bbox_contains_xy?(poly, {x, y})
  end

  defp bbox_contains_xy?(%Geo.Polygon{} = poly, {x, y}) do
    {min_x, max_x, min_y, max_y} = bbox_corners(poly)
    x >= min_x and x <= max_x and y >= min_y and y <= max_y
  end

  defp bbox_contains_bbox?(%Geo.Polygon{} = outer, %Geo.Polygon{} = inner) do
    {o_min_x, o_max_x, o_min_y, o_max_y} = bbox_corners(outer)
    {i_min_x, i_max_x, i_min_y, i_max_y} = bbox_corners(inner)
    o_min_x <= i_min_x and o_min_y <= i_min_y and o_max_x >= i_max_x and o_max_y >= i_max_y
  end

  defp bbox_corners(%Geo.Polygon{coordinates: [exterior | _]}) do
    xs = Enum.map(exterior, &elem(&1, 0))
    ys = Enum.map(exterior, &elem(&1, 1))
    {Enum.min(xs), Enum.max(xs), Enum.min(ys), Enum.max(ys)}
  end

  defp polygons(%Geo.MultiPolygon{coordinates: polys}) do
    Enum.map(polys, fn rings -> %Geo.Polygon{coordinates: rings, srid: 4326} end)
  end
end
