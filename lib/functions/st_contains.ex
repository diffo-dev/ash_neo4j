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

  # box-contains-multipoint — true iff every point of the MultiPoint lies
  # inside the Box. Useful for "are all of this device's sensors inside the
  # NSA?" — different semantics from st_intersects which is any-of.
  def evaluate(%{arguments: [%AshNeo4j.Type.Box{sw: sw, ne: ne}, %AshNeo4j.Type.MultiPoint{points: points}]}) do
    {:known,
     Enum.all?(points, fn p ->
       p.x >= sw.x and p.x <= ne.x and p.y >= sw.y and p.y <= ne.y
     end)}
  end

  # multibox-contains-point — any-of: true iff any constituent box contains
  # the point. This is the natural SQ semantic: "this customer falls in
  # one of the sub-regions making up the service area".
  def evaluate(%{arguments: [%AshNeo4j.Type.MultiBox{boxes: boxes}, %Bolty.Types.Point{} = p]}) do
    {:known, Enum.any?(boxes, &box_contains_point?(&1, p))}
  end

  # multibox-contains-box — any-of: true iff any constituent box fully
  # contains the inner box.
  def evaluate(%{arguments: [%AshNeo4j.Type.MultiBox{boxes: boxes}, %AshNeo4j.Type.Box{} = inner]}) do
    {:known, Enum.any?(boxes, &box_contains_box?(&1, inner))}
  end

  # multibox-contains-multipoint — every point must fall inside *some*
  # constituent box (the multibox covers the point set).
  def evaluate(%{arguments: [%AshNeo4j.Type.MultiBox{boxes: boxes}, %AshNeo4j.Type.MultiPoint{points: points}]}) do
    {:known, Enum.all?(points, fn p -> Enum.any?(boxes, &box_contains_point?(&1, p)) end)}
  end

  def evaluate(_), do: :unknown

  defp box_contains_point?(%AshNeo4j.Type.Box{sw: sw, ne: ne}, %Bolty.Types.Point{} = p) do
    p.x >= sw.x and p.x <= ne.x and p.y >= sw.y and p.y <= ne.y
  end

  defp box_contains_box?(%AshNeo4j.Type.Box{sw: o_sw, ne: o_ne}, %AshNeo4j.Type.Box{sw: i_sw, ne: i_ne}) do
    o_sw.x <= i_sw.x and o_sw.y <= i_sw.y and o_ne.x >= i_ne.x and o_ne.y >= i_ne.y
  end
end
