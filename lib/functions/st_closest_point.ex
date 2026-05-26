# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.StClosestPoint do
  @moduledoc """
  `st_closest_point(collection, point)` — returns the closest vertex from
  a multi-vertex geometry to a target point. Mirrors ash_geo / PostGIS
  `ST_ClosestPoint`. v1 supports `st_closest_point(%LineString{}, %Point{})`
  as closest **vertex** (an approximation; true closest-point-on-segment is
  a future refinement). MultiPoint support is added when that type lands.

  In-memory only — no Cypher pushdown in this slice. Returns `nil` if the
  collection is empty or either argument is nil.
  """
  use Ash.Query.Function, name: :st_closest_point, predicate?: false

  def args, do: [[:any, :any]]

  def returns, do: [:any]

  def evaluate(%{arguments: [nil, _]}), do: {:known, nil}
  def evaluate(%{arguments: [_, nil]}), do: {:known, nil}

  def evaluate(%{arguments: [%AshNeo4j.Type.LineString{vertices: vertices}, %Bolty.Types.Point{} = target]}) when vertices != [] do
    {:known, closest(vertices, target)}
  end

  def evaluate(_), do: :unknown

  defp closest(points, target) do
    Enum.min_by(points, fn p ->
      AshNeo4j.Functions.StDistance.evaluate(%{arguments: [p, target]})
      |> case do
        {:known, d} when is_number(d) -> d
        _ -> :infinity
      end
    end)
  end
end
