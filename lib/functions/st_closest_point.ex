# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.StClosestPoint do
  @moduledoc """
  `st_closest_point(collection, point)` — returns the closest vertex from
  a multi-vertex geometry to a target point. Mirrors ash_geo / PostGIS
  `ST_ClosestPoint`. v1 supports:

  - `st_closest_point(%MultiPoint{}, %Point{})` — exact (the collection
    IS a set of points; the closest "point" is genuinely one of them).
  - `st_closest_point(%LineString{}, %Point{})` — closest **vertex** (an
    approximation; true closest-point-on-segment is a future refinement).

  In-memory only — no Cypher pushdown in this slice. Returns `nil` if the
  collection is empty or either argument is nil.
  """
  use Ash.Query.Function, name: :st_closest_point, predicate?: false

  def args, do: [[:any, :any]]

  def returns, do: [:any]

  def evaluate(%{arguments: [nil, _]}), do: {:known, nil}
  def evaluate(%{arguments: [_, nil]}), do: {:known, nil}

  def evaluate(%{arguments: [%AshNeo4j.Type.MultiPoint{points: points}, %Geo.Point{} = target]}) when points != [] do
    {:known, closest_as_geo(points, target)}
  end

  def evaluate(%{arguments: [%AshNeo4j.Type.LineString{vertices: vertices}, %Geo.Point{} = target]}) when vertices != [] do
    {:known, closest_as_geo(vertices, target)}
  end

  def evaluate(_), do: :unknown

  # Picks the closest vertex to the target by haversine distance and returns
  # it as a %Geo.Point{} (regardless of whether the internal vertex was
  # stored as %Bolty.Types.Point{} or %Geo.Point{}). The internal Bolty
  # storage will go away when LineString/MultiPoint migrate to %Geo.*{}.
  defp closest_as_geo(vertices, target) do
    vertices
    |> Enum.min_by(fn v ->
      AshNeo4j.Functions.StDistance.evaluate(%{arguments: [as_geo(v), target]})
      |> case do
        {:known, d} when is_number(d) -> d
        _ -> :infinity
      end
    end)
    |> as_geo()
  end

  defp as_geo(%Geo.Point{} = p), do: p
  defp as_geo(%Bolty.Types.Point{x: x, y: y}), do: %Geo.Point{coordinates: {x, y}, srid: 4326}
end
