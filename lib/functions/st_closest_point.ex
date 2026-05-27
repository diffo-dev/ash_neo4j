# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.StClosestPoint do
  @moduledoc """
  `st_closest_point(collection, point)` — returns the closest vertex from
  a multi-vertex geometry to a target point. Mirrors ash_geo / PostGIS
  `ST_ClosestPoint`. v1 supports:

  - `st_closest_point(%Geo.MultiPoint{}, %Geo.Point{})` — exact (the
    collection IS a set of points; the closest "point" is genuinely one
    of them).
  - `st_closest_point(%Geo.LineString{}, %Geo.Point{})` — closest
    **vertex** (an approximation; true closest-point-on-segment is a
    future refinement).

  In-memory only — no Cypher pushdown in this slice. Returns `nil` if
  the collection is empty or either argument is nil. Always returns the
  result as a `%Geo.Point{srid: 4326}` regardless of the collection's
  internal representation.
  """
  use Ash.Query.Function, name: :st_closest_point, predicate?: false

  def args, do: [[:any, :any]]

  def returns, do: [:any]

  def evaluate(%{arguments: [nil, _]}), do: {:known, nil}
  def evaluate(%{arguments: [_, nil]}), do: {:known, nil}

  def evaluate(%{arguments: [%Geo.MultiPoint{coordinates: coords}, %Geo.Point{coordinates: target}]}) when coords != [] do
    {:known, closest_as_geo(coords, target)}
  end

  def evaluate(%{arguments: [%Geo.LineString{coordinates: coords}, %Geo.Point{coordinates: target}]}) when coords != [] do
    {:known, closest_as_geo(coords, target)}
  end

  def evaluate(_), do: :unknown

  defp closest_as_geo(coords, target) do
    {x, y} = Enum.min_by(coords, &haversine_xy(&1, target))
    %Geo.Point{coordinates: {x, y}, srid: 4326}
  end

  defp haversine_xy({lng1, lat1}, {lng2, lat2}) do
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
