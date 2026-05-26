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

  def evaluate(%{arguments: [%AshNeo4j.Type.Box{} = box, %Geo.Point{} = p]}) do
    {:known, box_contains_point?(box, p)}
  end

  def evaluate(%{arguments: [%AshNeo4j.Type.Box{sw: o_sw, ne: o_ne}, %AshNeo4j.Type.Box{sw: i_sw, ne: i_ne}]}) do
    {:known,
     o_sw.x <= i_sw.x and o_sw.y <= i_sw.y and
       o_ne.x >= i_ne.x and o_ne.y >= i_ne.y}
  end

  # box-contains-multipoint — true iff every point of the MultiPoint lies
  # inside the Box. Useful for "are all of this device's sensors inside the
  # NSA?" — different semantics from st_intersects which is any-of.
  def evaluate(%{arguments: [%AshNeo4j.Type.Box{} = box, %AshNeo4j.Type.MultiPoint{points: points}]}) do
    {:known, Enum.all?(points, &box_contains_point?(box, &1))}
  end

  # multibox-contains-point — any-of: true iff any constituent box contains
  # the point. This is the natural SQ semantic: "this customer falls in
  # one of the sub-regions making up the service area".
  def evaluate(%{arguments: [%AshNeo4j.Type.MultiBox{boxes: boxes}, %Geo.Point{} = p]}) do
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

  # Accepts either a %Geo.Point{} (user-facing API since v2) or a
  # %Bolty.Types.Point{} (still held internally by MultiPoint vertices
  # until that type migrates in a later commit). Coordinates are
  # extracted to (x, y) and compared against the Box corners.
  defp box_contains_point?(%AshNeo4j.Type.Box{sw: sw, ne: ne}, point) do
    {x, y} = to_xy(point)
    x >= sw.x and x <= ne.x and y >= sw.y and y <= ne.y
  end

  defp box_contains_box?(%AshNeo4j.Type.Box{sw: o_sw, ne: o_ne}, %AshNeo4j.Type.Box{sw: i_sw, ne: i_ne}) do
    o_sw.x <= i_sw.x and o_sw.y <= i_sw.y and o_ne.x >= i_ne.x and o_ne.y >= i_ne.y
  end

  defp to_xy(%Geo.Point{coordinates: {x, y}}), do: {x, y}
  defp to_xy(%Bolty.Types.Point{x: x, y: y}), do: {x, y}
end
