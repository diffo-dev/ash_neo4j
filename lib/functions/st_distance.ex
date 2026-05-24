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

  def evaluate(%{arguments: [%Bolty.Types.Point{srid: 4326} = p1, %Bolty.Types.Point{srid: 4326} = p2]}) do
    {:known, haversine_meters(p1, p2)}
  end

  def evaluate(_), do: :unknown

  # Haversine on a spherical Earth — matches Neo4j's `point.distance` for WGS-84 2D.
  defp haversine_meters(%Bolty.Types.Point{x: lng1, y: lat1}, %Bolty.Types.Point{x: lng2, y: lat2}) do
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
end
