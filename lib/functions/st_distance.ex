# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.StDistance do
  @moduledoc """
  Geodesic distance between two points, in meters. Mirrors ash_geo /
  PostGIS `ST_Distance`. v1 supports point-point only.

      Place
      |> Ash.Query.filter(st_distance(location, ^customer_point) < 5_000)
      |> Ash.read!()

  When used inside a comparison filter (`<`, `<=`, `>`, `>=`, `==`), the
  whole comparison pushes down to Neo4j's native
  `point.distance(p1, p2) <op> threshold` — geodesic haversine in WGS-84,
  no Elixir-side math.

  Other contexts (`order_by`, `calculate`, comparisons against non-numeric
  RHS) fall back to in-memory `evaluate/1` using the same haversine formula.
  Pushdown in those contexts is future work.
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
  def evaluate(%{arguments: [%AshNeo4j.Type.LineString{vertices: vertices}, %Geo.Point{} = p]}) when vertices != [] do
    {:known, min_vertex_distance(vertices, p)}
  end

  def evaluate(%{arguments: [%Geo.Point{} = p, %AshNeo4j.Type.LineString{vertices: vertices}]}) when vertices != [] do
    {:known, min_vertex_distance(vertices, p)}
  end

  def evaluate(%{arguments: [%AshNeo4j.Type.MultiPoint{points: points}, %Geo.Point{} = p]}) when points != [] do
    {:known, min_vertex_distance(points, p)}
  end

  def evaluate(%{arguments: [%Geo.Point{} = p, %AshNeo4j.Type.MultiPoint{points: points}]}) when points != [] do
    {:known, min_vertex_distance(points, p)}
  end

  def evaluate(_), do: :unknown

  defp min_vertex_distance(vertices, target) do
    vertices
    |> Enum.map(&haversine_meters(&1, target))
    |> Enum.min()
  end

  # Haversine on a spherical Earth — matches Neo4j's `point.distance` for WGS-84 2D.
  # Accepts either %Geo.Point{} (user-facing API since v2) or %Bolty.Types.Point{}
  # (still held internally by LineString/MultiPoint vertices until those types
  # migrate in later commits).
  defp haversine_meters(a, b) do
    {lng1, lat1} = to_xy(a)
    {lng2, lat2} = to_xy(b)

    earth_radius_m = 6_371_000.0
    rad_lat1 = :math.pi() / 180 * lat1
    rad_lat2 = :math.pi() / 180 * lat2
    delta_lat = :math.pi() / 180 * (lat2 - lat1)
    delta_lng = :math.pi() / 180 * (lng2 - lng1)

    a =
      :math.sin(delta_lat / 2) ** 2 +
        :math.cos(rad_lat1) * :math.cos(rad_lat2) * :math.sin(delta_lng / 2) ** 2

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))

    earth_radius_m * c
  end

  defp to_xy(%Geo.Point{coordinates: {x, y}}), do: {x, y}
  defp to_xy(%Bolty.Types.Point{x: x, y: y}), do: {x, y}
end
