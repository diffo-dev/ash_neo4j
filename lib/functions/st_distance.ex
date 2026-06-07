# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.StDistance do
  @moduledoc """
  Geodesic distance between two geometries, in meters. Mirrors ash_geo /
  PostGIS `ST_Distance`. Post #274 every geometry arrives as a
  `%Geo.*{}` struct.

      Place
      |> Ash.Query.filter(st_distance(location, ^customer_point) < 5_000)
      |> Ash.read!()

  When used inside a comparison filter (`<`, `<=`, `>`, `>=`, `==`,
  `!=`) against a Point attribute, the whole comparison pushes down to
  Neo4j's native `point.distance(p1, p2) <op> threshold` (geodesic
  haversine in WGS-84) via the `<attr>.point` indexable companion.

  ## In-memory coverage (#279)

  Any geometry **to a Point** is supported and exact at this scale:

    * Point — geodesic haversine.
    * LineString / MultiLineString — true closest-point-on-**segment**
      (not closest-vertex), so a point near a long edge's midpoint reads
      its real perpendicular distance rather than the overstated
      distance to the nearest vertex.
    * MultiPoint — distance to the nearest point of the set.
    * Polygon / MultiPolygon — `0.0` when the point is inside (hole-aware
      via `topo`), otherwise the distance to the nearest boundary edge
      (over the exterior ring and any holes).

  Distances between two **non-Point** geometries (line↔line,
  line↔polygon, polygon↔polygon) need segment-to-segment math and stay
  `:unknown` for now — deferred in #279.
  """
  use Ash.Query.Function, name: :st_distance, predicate?: false

  @to_point [
    Geo.Point,
    Geo.LineString,
    Geo.MultiPoint,
    Geo.MultiLineString,
    Geo.Polygon,
    Geo.MultiPolygon
  ]

  def args, do: [[:any, :any]]

  def returns, do: [:float]

  def evaluate(%{arguments: [nil, _]}), do: {:known, nil}
  def evaluate(%{arguments: [_, nil]}), do: {:known, nil}

  # WGS-84-3D point ↔ point (#270). Matches Neo4j's 3D point.distance so the
  # in-memory re-filter agrees with the pushdown. PointZ ↔ 2D Point is *not*
  # matched here — a dimension mix is caught up front (GeoDimensionMismatch).
  def evaluate(%{arguments: [%Geo.PointZ{coordinates: a}, %Geo.PointZ{coordinates: b}]}) do
    known(AshNeo4j.Geo.haversine_meters_3d(a, b))
  end

  # Point ↔ any supported geometry (including Point ↔ Point). Symmetric.
  def evaluate(%{arguments: [%Geo.Point{} = point, %g{} = geo]}) when g in @to_point do
    known(geometry_point_meters(geo, point))
  end

  def evaluate(%{arguments: [%g{} = geo, %Geo.Point{} = point]}) when g in @to_point do
    known(geometry_point_meters(geo, point))
  end

  def evaluate(_), do: :unknown

  # :infinity is the "no measurable geometry" sentinel (empty coords); it
  # orders above every real distance under min/2, so it only survives when
  # there's genuinely nothing to measure — surfaced honestly as :unknown.
  defp known(:infinity), do: :unknown
  defp known(distance) when is_number(distance), do: {:known, distance}

  defp geometry_point_meters(%Geo.Point{coordinates: a}, %Geo.Point{coordinates: b}) do
    AshNeo4j.Geo.haversine_meters(a, b)
  end

  defp geometry_point_meters(%Geo.MultiPoint{coordinates: coords}, %Geo.Point{coordinates: b}) do
    coords |> Enum.map(&AshNeo4j.Geo.haversine_meters(&1, b)) |> safe_min()
  end

  defp geometry_point_meters(%Geo.LineString{coordinates: coords}, %Geo.Point{coordinates: b}) do
    AshNeo4j.Geo.min_segment_meters(b, coords)
  end

  defp geometry_point_meters(%Geo.MultiLineString{coordinates: lines}, %Geo.Point{coordinates: b}) do
    lines |> Enum.map(&AshNeo4j.Geo.min_segment_meters(b, &1)) |> safe_min()
  end

  defp geometry_point_meters(%Geo.Polygon{coordinates: rings} = poly, %Geo.Point{coordinates: b} = point) do
    if Topo.contains?(poly, point), do: 0.0, else: nearest_edge(rings, b)
  end

  defp geometry_point_meters(%Geo.MultiPolygon{coordinates: polygons} = multi, %Geo.Point{coordinates: b} = point) do
    if Topo.contains?(multi, point), do: 0.0, else: polygons |> Enum.concat() |> nearest_edge(b)
  end

  # Distance to the nearest edge over a set of rings (exterior + holes):
  # a point in a hole is outside the polygon, and the hole ring is part of
  # the boundary, so the min over all rings is the correct boundary distance.
  defp nearest_edge(rings, b) do
    rings |> Enum.map(&AshNeo4j.Geo.min_segment_meters(b, &1)) |> safe_min()
  end

  defp safe_min([]), do: :infinity
  defp safe_min(distances), do: Enum.min(distances)
end
