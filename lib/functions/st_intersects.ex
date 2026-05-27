# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.StIntersects do
  @moduledoc """
  `st_intersects(a, b)` — true if two geometries share any space. Mirrors
  ash_geo / PostGIS `ST_Intersects`. Exact, via
  [`topo`](https://hex.pm/packages/topo) on the `%Geo.*{}` geometries
  (#267) — handles any combination of Point / LineString / Polygon /
  Multi* directly, including segment-edge crossings.

      Place
      |> Ash.Query.filter(st_intersects(bounds, ^other_polygon))
      |> Ash.read!()

  Evaluates in memory. Unlike `st_contains`, `st_intersects` is **not**
  pushed down — a bbox-overlap prefilter via the `bbSW`/`bbNE` companions
  is tractable (`point.withinBBox` on the corners) but deferred to a
  follow-up. In-memory `topo` is correct and fast at NBN scale.

  Notably, a LineString that crosses a Polygon **without** a vertex
  inside it now correctly intersects (the old vertex-in-bbox
  approximation missed that case).
  """
  use Ash.Query.Function, name: :st_intersects, predicate?: true

  @geo_structs [
    Geo.Point,
    Geo.LineString,
    Geo.Polygon,
    Geo.MultiPoint,
    Geo.MultiLineString,
    Geo.MultiPolygon
  ]

  def args, do: [[:any, :any]]

  def returns, do: [:boolean]

  def evaluate(%{arguments: [nil, _]}), do: {:known, false}
  def evaluate(%{arguments: [_, nil]}), do: {:known, false}

  def evaluate(%{arguments: [%a{} = ga, %b{} = gb]})
      when a in @geo_structs and b in @geo_structs do
    {:known, Topo.intersects?(ga, gb)}
  end

  def evaluate(_), do: :unknown
end
