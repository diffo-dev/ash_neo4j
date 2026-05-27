# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Geo do
  @moduledoc """
  Geodesic geometry primitives for the in-memory side of AshNeo4j's
  spatial predicates.

  The single source of truth for distance math. The in-memory `st_*`
  functions (`st_distance`, `st_dwithin`, `st_closest_point`) use these
  so they agree with the values Neo4j returns on the pushdown path.

  ## Matching Neo4j's distance model

  Neo4j's `point.distance/2` for WGS-84 geographic points is a spherical
  haversine on the **WGS-84 equatorial radius** (the semi-major axis,
  6 378 137 m) — *not* the mean Earth radius (6 371 000 m) a naive
  haversine would reach for. Using the mean radius disagrees with Neo4j
  by ~0.11 % (≈800 m over a 700 km span), which means the same
  `st_distance` query would return different answers depending on
  whether it pushed down to Cypher or evaluated in Elixir.

  We deliberately use the same radius Neo4j does, so the two execution
  paths agree to sub-metre over continental distances. Neo4j's model is
  spherical, not ellipsoidal — true ellipsoidal distance (Vincenty /
  Karney) would differ by a further ~0.1–0.5 %, but since we push down
  to Neo4j, Neo4j's model is the reference we match.
  """

  # WGS-84 semi-major axis (equatorial radius), in metres — the sphere
  # radius Neo4j's point.distance uses for geographic points.
  @wgs_84_equatorial_radius_m 6_378_137.0

  @doc """
  Geodesic (great-circle haversine) distance in metres between two
  WGS-84 `{lng, lat}` coordinate pairs. Matches Neo4j's
  `point.distance/2` to sub-metre over continental distances.
  """
  @spec haversine_meters({number(), number()}, {number(), number()}) :: float()
  def haversine_meters({lng1, lat1}, {lng2, lat2}) do
    rad_lat1 = :math.pi() / 180 * lat1
    rad_lat2 = :math.pi() / 180 * lat2
    delta_lat = :math.pi() / 180 * (lat2 - lat1)
    delta_lng = :math.pi() / 180 * (lng2 - lng1)

    a =
      :math.sin(delta_lat / 2) ** 2 +
        :math.cos(rad_lat1) * :math.cos(rad_lat2) * :math.sin(delta_lng / 2) ** 2

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))

    @wgs_84_equatorial_radius_m * c
  end

  @doc """
  Geodesic distance in metres from point `p` to the nearest point on the
  segment `a`–`b` (each a `{lng, lat}` pair) — the true
  closest-point-on-segment distance, not closest-vertex.

  The closest point is found by projecting `p` onto the segment in a
  local equirectangular frame (longitude scaled by `cos(lat)` so the
  projection isn't distorted by meridian convergence), then the distance
  to that point is measured with `haversine_meters/2`. Accurate for the
  short segments of fibre paths and admin-boundary edges; a degenerate
  segment (`a == b`) falls back to the distance to `a`.
  """
  @spec point_segment_meters({number(), number()}, {number(), number()}, {number(), number()}) :: float()
  def point_segment_meters(p, a, b) do
    haversine_meters(p, closest_point_on_segment(p, a, b))
  end

  @doc """
  The point on segment `a`–`b` closest to `p`, as a `{lng, lat}` pair.
  Clamps to the segment's endpoints. See `point_segment_meters/3` for the
  projection model.
  """
  @spec closest_point_on_segment({number(), number()}, {number(), number()}, {number(), number()}) ::
          {number(), number()}
  def closest_point_on_segment({px, py}, {ax, ay} = _a, {bx, by} = _b) do
    # Scale longitude into a local planar frame so the projection isn't
    # stretched by meridian convergence at the segment's latitude.
    scale = :math.cos(:math.pi() / 180 * ((ay + by) / 2))
    dx = (bx - ax) * scale
    dy = by - ay
    denom = dx * dx + dy * dy

    t =
      if denom == 0.0 do
        0.0
      else
        ((px - ax) * scale * dx + (py - ay) * dy) / denom
      end
      |> max(0.0)
      |> min(1.0)

    {ax + t * (bx - ax), ay + t * (by - ay)}
  end

  @doc """
  Minimum `point_segment_meters/3` from `p` to any segment formed by
  consecutive vertices of `coords` (a list of `{lng, lat}` pairs). Used
  for point-to-LineString and point-to-polygon-ring-edge distance. A
  single-vertex list degenerates to the distance to that vertex; an empty
  list returns `:infinity` (a sentinel that orders above any real distance
  under `min/2`, so callers can fold it away).
  """
  @spec min_segment_meters({number(), number()}, [{number(), number()}]) :: float() | :infinity
  def min_segment_meters(_p, []), do: :infinity
  def min_segment_meters(p, [only]), do: haversine_meters(p, only)

  def min_segment_meters(p, coords) when is_list(coords) do
    coords
    |> Enum.zip(tl(coords))
    |> Enum.reduce(:infinity, fn {a, b}, acc -> min(acc, point_segment_meters(p, a, b)) end)
  end
end
