# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.StIntersects do
  @moduledoc """
  `st_intersects(a, b)` — true if two geometries share any space. Mirrors
  ash_geo / PostGIS `ST_Intersects`. v1 supports box-box.

      Place
      |> Ash.Query.filter(st_intersects(bounds, ^other_box))
      |> Ash.read!()

  No Cypher pushdown in this slice — the predicate evaluates in memory via
  `Ash.Filter.Runtime`. Pushdown is tractable (4 axis comparisons on the
  bbox companions) but deferred; in-memory is correct and fast at NBN scale.

  For LineString and MultiPoint v1, intersection with a Box is approximated
  as "any vertex of the collection lies inside the Box" — under-approximates
  (misses cases where a segment crosses the box without a vertex inside).
  For typical densely-sampled fibre paths against typical service-area
  boxes, the approximation is fine; precise segment-edge crossing is future
  work.
  """
  use Ash.Query.Function, name: :st_intersects, predicate?: true

  def args, do: [[:any, :any]]

  def returns, do: [:boolean]

  def evaluate(%{arguments: [nil, _]}), do: {:known, false}
  def evaluate(%{arguments: [_, nil]}), do: {:known, false}

  def evaluate(%{arguments: [%AshNeo4j.Type.Box{sw: a_sw, ne: a_ne}, %AshNeo4j.Type.Box{sw: b_sw, ne: b_ne}]}) do
    {:known,
     a_ne.x >= b_sw.x and a_sw.x <= b_ne.x and
       a_ne.y >= b_sw.y and a_sw.y <= b_ne.y}
  end

  # LineString intersection with Box — v1 approximation: true if any vertex
  # of the line lies inside the Box. Symmetric.
  def evaluate(%{arguments: [%AshNeo4j.Type.LineString{vertices: vertices}, %AshNeo4j.Type.Box{} = box]}) do
    {:known, Enum.any?(vertices, &point_in_box?(&1, box))}
  end

  def evaluate(%{arguments: [%AshNeo4j.Type.Box{} = box, %AshNeo4j.Type.LineString{vertices: vertices}]}) do
    {:known, Enum.any?(vertices, &point_in_box?(&1, box))}
  end

  def evaluate(_), do: :unknown

  defp point_in_box?(%Bolty.Types.Point{} = p, %AshNeo4j.Type.Box{sw: sw, ne: ne}) do
    p.x >= sw.x and p.x <= ne.x and p.y >= sw.y and p.y <= ne.y
  end
end
