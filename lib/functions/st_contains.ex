# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.StContains do
  @moduledoc """
  Spatial containment — true if the first geometry contains the second.

  v1 supports box-contains-point:

      Place
      |> Ash.Query.filter(st_contains(bounds, ^test_point))
      |> Ash.read!()

  Pushes down to Neo4j's native `point.withinBBox(point, lowerLeft, upperRight)`
  via the data layer's `:within_bbox` operator path. Falls back to in-memory
  evaluation when the data layer can't push it down.

  Named after the OGC / PostGIS convention (`ST_Contains`) for consistency
  with ash_geo so consumer code reads the same across data layers.
  """
  use Ash.Query.Function, name: :st_contains, predicate?: true

  def args, do: [[:any, :any]]

  def returns, do: [:boolean]

  def evaluate(%{arguments: [nil, _]}), do: {:known, false}
  def evaluate(%{arguments: [_, nil]}), do: {:known, false}

  def evaluate(%{arguments: [%AshNeo4j.Type.Box{sw: sw, ne: ne}, %Bolty.Types.Point{} = p]}) do
    {:known, p.x >= sw.x and p.x <= ne.x and p.y >= sw.y and p.y <= ne.y}
  end

  def evaluate(_), do: :unknown
end
