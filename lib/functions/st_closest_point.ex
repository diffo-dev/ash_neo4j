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
  - `st_closest_point(%Geo.LineString{}, %Geo.Point{})` — the true
    closest point **on the nearest segment** (#279), which may be an
    interior point of an edge, not just a vertex.

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

  def evaluate(%{arguments: [%Geo.MultiPoint{coordinates: coords}, %Geo.Point{coordinates: target}]})
      when coords != [] do
    {:known, closest_as_geo(coords, target)}
  end

  def evaluate(%{arguments: [%Geo.LineString{coordinates: coords}, %Geo.Point{coordinates: target}]})
      when coords != [] do
    {:known, closest_on_path(coords, target)}
  end

  def evaluate(_), do: :unknown

  # MultiPoint: the answer is genuinely one of the vertices.
  defp closest_as_geo(coords, target) do
    {x, y} = Enum.min_by(coords, &AshNeo4j.Geo.haversine_meters(&1, target))
    %Geo.Point{coordinates: {x, y}, srid: 4326}
  end

  # LineString: the closest point lies on the nearest segment (possibly an
  # interior point of an edge). A single-vertex path degenerates to that
  # vertex.
  defp closest_on_path([only], _target), do: %Geo.Point{coordinates: only, srid: 4326}

  defp closest_on_path(coords, target) do
    {x, y} =
      coords
      |> Enum.zip(tl(coords))
      |> Enum.map(fn {a, b} -> AshNeo4j.Geo.closest_point_on_segment(target, a, b) end)
      |> Enum.min_by(&AshNeo4j.Geo.haversine_meters(&1, target))

    %Geo.Point{coordinates: {x, y}, srid: 4326}
  end
end
