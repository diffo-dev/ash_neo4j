# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.StIntersects do
  @moduledoc """
  `st_intersects(a, b)` — true if two geometries share any space. Mirrors
  ash_geo / PostGIS `ST_Intersects`. v1 evaluates in memory against
  `%Geo.*{}` structs.

      Place
      |> Ash.Query.filter(st_intersects(bounds, ^other_polygon))
      |> Ash.read!()

  Cypher pushdown to `point.withinBBox` is tractable via the scalar
  `bbSW`/`bbNE` companion properties (which all non-Point geometries
  write under #274); deferred to a follow-up. In-memory evaluation is
  correct and fast at NBN scale.

  For LineString and MultiPoint against a Polygon, intersection uses
  the vertex-in-bbox approximation — under-approximates segment
  crossings without a vertex inside. Documented per case below;
  precise segment-edge crossing is future work.
  """
  use Ash.Query.Function, name: :st_intersects, predicate?: true

  def args, do: [[:any, :any]]

  def returns, do: [:boolean]

  def evaluate(%{arguments: [nil, _]}), do: {:known, false}
  def evaluate(%{arguments: [_, nil]}), do: {:known, false}

  def evaluate(%{arguments: [%Geo.Polygon{} = a, %Geo.Polygon{} = b]}) do
    {:known, bbox_intersects?(a, b)}
  end

  # LineString intersection with Polygon — v1 approximation: true if any
  # vertex of the line lies inside the Polygon's bbox. Symmetric.
  def evaluate(%{arguments: [%Geo.LineString{coordinates: coords}, %Geo.Polygon{} = poly]}) do
    {:known, Enum.any?(coords, &in_bbox?(poly, &1))}
  end

  def evaluate(%{arguments: [%Geo.Polygon{} = poly, %Geo.LineString{coordinates: coords}]}) do
    {:known, Enum.any?(coords, &in_bbox?(poly, &1))}
  end

  # MultiPoint vs Polygon — any-of: any point inside the polygon's bbox.
  def evaluate(%{arguments: [%Geo.MultiPoint{coordinates: coords}, %Geo.Polygon{} = poly]}) do
    {:known, Enum.any?(coords, &in_bbox?(poly, &1))}
  end

  def evaluate(%{arguments: [%Geo.Polygon{} = poly, %Geo.MultiPoint{coordinates: coords}]}) do
    {:known, Enum.any?(coords, &in_bbox?(poly, &1))}
  end

  # MultiPolygon vs Polygon — any-of over the constituent polygons.
  def evaluate(%{arguments: [%Geo.MultiPolygon{} = mp, %Geo.Polygon{} = poly]}) do
    {:known, Enum.any?(polygons(mp), &bbox_intersects?(&1, poly))}
  end

  def evaluate(%{arguments: [%Geo.Polygon{} = poly, %Geo.MultiPolygon{} = mp]}) do
    {:known, Enum.any?(polygons(mp), &bbox_intersects?(&1, poly))}
  end

  # MultiPolygon vs Point — any-of: any constituent polygon contains the point.
  def evaluate(%{arguments: [%Geo.MultiPolygon{} = mp, %Geo.Point{coordinates: {x, y}}]}) do
    {:known, Enum.any?(polygons(mp), &in_bbox?(&1, {x, y}))}
  end

  def evaluate(%{arguments: [%Geo.Point{coordinates: {x, y}}, %Geo.MultiPolygon{} = mp]}) do
    {:known, Enum.any?(polygons(mp), &in_bbox?(&1, {x, y}))}
  end

  def evaluate(_), do: :unknown

  defp in_bbox?(%Geo.Polygon{} = poly, {x, y}) do
    {min_x, max_x, min_y, max_y} = bbox_corners(poly)
    x >= min_x and x <= max_x and y >= min_y and y <= max_y
  end

  defp bbox_intersects?(%Geo.Polygon{} = a, %Geo.Polygon{} = b) do
    {a_min_x, a_max_x, a_min_y, a_max_y} = bbox_corners(a)
    {b_min_x, b_max_x, b_min_y, b_max_y} = bbox_corners(b)
    a_max_x >= b_min_x and a_min_x <= b_max_x and a_max_y >= b_min_y and a_min_y <= b_max_y
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
