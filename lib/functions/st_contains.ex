# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.StContains do
  @moduledoc """
  Spatial containment — true if the first geometry contains the second.

      Place
      |> Ash.Query.filter(st_contains(bounds, ^test_point))
      |> Ash.read!()

  Exact, hole-aware containment via [`topo`](https://hex.pm/packages/topo)
  on the `%Geo.*{}` geometries (#267). Supports `%Geo.Polygon{}` and
  `%Geo.MultiPolygon{}` as the container, against any of `%Geo.Point{}`,
  `%Geo.MultiPoint{}`, `%Geo.LineString{}`, `%Geo.MultiLineString{}`,
  `%Geo.Polygon{}`, or `%Geo.MultiPolygon{}`. OGC `contains` semantics:

  - `st_contains(polygon, multipoint)` is true iff **every** point lies
    inside the polygon (all-of).
  - `st_contains(multipolygon, point)` is true iff the point lies in
    **any** constituent polygon (any-of).
  - Containment respects interior rings — a point in a hole is **not**
    contained.

  Inside an `Ash.Query.filter`, the `bbSW`/`bbNE` companions drive a
  cheap indexed `point.withinBBox` **prefilter** in Cypher (over-selects
  candidates whose bounding box contains the test geometry); the exact
  `topo` test then runs in-memory over the prefilter's candidates. A true
  match always lies within the polygon's bbox, so the prefilter never
  drops one — it only narrows the set the exact test runs against.

  Named after the OGC / PostGIS convention (`ST_Contains`) for
  consistency with ash_geo / `AshGeo.Postgis` so consumer code reads
  the same across data layers.
  """
  use Ash.Query.Function, name: :st_contains, predicate?: true

  def args, do: [[:any, :any]]

  def returns, do: [:boolean]

  def evaluate(%{arguments: [nil, _]}), do: {:known, false}
  def evaluate(%{arguments: [_, nil]}), do: {:known, false}

  def evaluate(%{arguments: [%container{} = a, %contained{} = b]})
      when container in [Geo.Polygon, Geo.MultiPolygon] and
             contained in [
               Geo.Point,
               Geo.MultiPoint,
               Geo.LineString,
               Geo.MultiLineString,
               Geo.Polygon,
               Geo.MultiPolygon
             ] do
    {:known, Topo.contains?(a, b)}
  end

  def evaluate(_), do: :unknown
end
