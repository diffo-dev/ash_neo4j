# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.StDistance do
  @moduledoc """
  Geodesic distance between two points, in meters. Mirrors ash_geo /
  PostGIS `ST_Distance`. v1 supports point-point + closest-vertex
  distance for LineString and MultiPoint (post #274 rearchitecture all
  geometry types arrive as `%Geo.*{}` structs).

      Place
      |> Ash.Query.filter(st_distance(location, ^customer_point) < 5_000)
      |> Ash.read!()

  When used inside a comparison filter (`<`, `<=`, `>`, `>=`, `==`,
  `!=`) against a Point attribute, the whole comparison pushes down to
  Neo4j's native `point.distance(p1, p2) <op> threshold` (geodesic
  haversine in WGS-84) via the `<attr>.point` indexable companion.

  LineString and MultiPoint reach the in-memory `evaluate/1` clauses
  below — closest-vertex approximation, fine at NBN scale.
  """
  use Ash.Query.Function, name: :st_distance, predicate?: false

  def args, do: [[:any, :any]]

  def returns, do: [:float]

  def evaluate(%{arguments: [nil, _]}), do: {:known, nil}
  def evaluate(%{arguments: [_, nil]}), do: {:known, nil}

  def evaluate(%{arguments: [%Geo.Point{} = p1, %Geo.Point{} = p2]}) do
    {:known, haversine_meters(p1, p2)}
  end

  # LineString / MultiPoint to point — closest-vertex distance. Symmetric.
  # For LineString this is a v1 approximation; true closest-point-on-segment
  # is a future refinement. For MultiPoint the closest vertex *is* the
  # closest point by definition.
  def evaluate(%{arguments: [%Geo.LineString{coordinates: coords}, %Geo.Point{} = p]}) when coords != [] do
    {:known, min_vertex_distance(coords, p)}
  end

  def evaluate(%{arguments: [%Geo.Point{} = p, %Geo.LineString{coordinates: coords}]}) when coords != [] do
    {:known, min_vertex_distance(coords, p)}
  end

  def evaluate(%{arguments: [%Geo.MultiPoint{coordinates: coords}, %Geo.Point{} = p]}) when coords != [] do
    {:known, min_vertex_distance(coords, p)}
  end

  def evaluate(%{arguments: [%Geo.Point{} = p, %Geo.MultiPoint{coordinates: coords}]}) when coords != [] do
    {:known, min_vertex_distance(coords, p)}
  end

  def evaluate(_), do: :unknown

  defp min_vertex_distance(coords, %Geo.Point{coordinates: target}) do
    coords
    |> Enum.map(&AshNeo4j.Geo.haversine_meters(&1, target))
    |> Enum.min()
  end

  # Matches Neo4j's `point.distance` for WGS-84 2D — see AshNeo4j.Geo,
  # the single source of truth for the radius the pushdown path uses.
  defp haversine_meters(%Geo.Point{coordinates: a}, %Geo.Point{coordinates: b}) do
    AshNeo4j.Geo.haversine_meters(a, b)
  end
end
