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

  def evaluate(_), do: :unknown
end
