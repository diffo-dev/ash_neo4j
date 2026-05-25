# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.StContains do
  @moduledoc """
  Spatial containment — true if the first geometry contains the second.

  v1 supports box-contains-point and box-contains-box:

      Place
      |> Ash.Query.filter(st_contains(bounds, ^test_point))
      |> Ash.read!()

      Place
      |> Ash.Query.filter(st_contains(bounds, ^test_box))
      |> Ash.read!()

  Both forms push down to Neo4j's native `point.withinBBox`:
  box-contains-point as a single call, box-contains-box as two ANDed calls
  on the inner box's SW and NE corners (which is sufficient for axis-aligned
  boxes — the other two corners are implied). `evaluate/1` covers the same
  cases for in-memory fallback when pushdown isn't taken (e.g. expressions
  the data layer can't recognise).

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

  def evaluate(%{arguments: [%AshNeo4j.Type.Box{sw: o_sw, ne: o_ne}, %AshNeo4j.Type.Box{sw: i_sw, ne: i_ne}]}) do
    {:known,
     o_sw.x <= i_sw.x and o_sw.y <= i_sw.y and
       o_ne.x >= i_ne.x and o_ne.y >= i_ne.y}
  end

  def evaluate(_), do: :unknown
end
