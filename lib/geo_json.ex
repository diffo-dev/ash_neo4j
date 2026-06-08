# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.GeoJson do
  @moduledoc """
  RFC 7946 GeoJSON encoder/decoder over the `:geo` library.

  `Geo.JSON.encode!/1` produces the obsolete 2008-spec GeoJSON shape when
  `srid` is set on a geometry struct — it adds a `"crs"` member that
  [RFC 7946](https://datatracker.ietf.org/doc/html/rfc7946) explicitly
  removed. AshNeo4j wants RFC 7946 strictly on disk (GIS-tool interop is
  half the motivation), so this module wraps `Geo.JSON` to:

    - **Strip the `crs` member on encode** by nilling `srid` before
      handing the struct to `Geo.JSON.encode!/1`.
    - **Add the optional RFC `bbox` member** to every encoded geometry,
      derived from the coordinates. Makes the JSON self-describing for
      any consumer that doesn't want to recompute the bounding box.
    - **Set `srid: 4326` on decoded structs.** AshNeo4j is WGS-84 2D
      throughout; the struct should carry that explicitly even though
      the on-disk JSON omits the CRS.

  Round-trip: `encode!(geom) |> decode!() == geom` (with `srid: 4326`
  set on the decoded side).

  The encode workaround is a candidate for an upstream fix in `:geo`
  itself (an option like `Geo.JSON.encode!(geom, rfc7946: true)`); to
  be filed once this local workaround is exercised in production.
  """

  @wgs_84_2d 4326
  @wgs_84_3d 4979

  @doc """
  Encodes a `%Geo.*{}` struct to an RFC 7946-compliant GeoJSON string
  with the `bbox` member included. Keys are sorted alphabetically via
  `AshNeo4j.Util.json_encode/1` for stable on-disk ordering.
  """
  @spec encode!(Geo.geometry()) :: String.t()
  def encode!(geom) do
    map = encode_map(geom)
    {:ok, json} = AshNeo4j.Util.json_encode(map)
    json
  end

  @doc """
  Encodes a `%Geo.*{}` struct to an RFC 7946 GeoJSON **map** (without
  JSON-stringifying). Used when the GeoJSON needs to be nested inside
  another structure that will itself be JSON-encoded — e.g. a Geo struct
  living inside a TypedStruct attribute, where the parent's JSON blob
  contains the nested GeoJSON inline.
  """
  @spec encode_map(Geo.geometry()) :: map()
  def encode_map(geom) do
    geom
    |> Map.put(:srid, nil)
    |> Geo.JSON.encode!()
    |> Map.put("bbox", bbox(geom))
  end

  @doc """
  Decodes an RFC 7946 GeoJSON string to a `%Geo.*{}` struct with the WGS-84
  srid set by dimensionality — `4326` for 2D geometries, `4979` for 3D (a
  third coordinate present, e.g. `%Geo.PointZ{}`). The on-disk JSON omits the
  CRS member (RFC 7946), so the srid is inferred from the coordinate arity and
  restored here. The `bbox` member, if present, is ignored — it's metadata
  derivable from coordinates and the struct doesn't carry it.
  """
  @spec decode!(String.t()) :: Geo.geometry()
  def decode!(json) when is_binary(json) do
    geom =
      json
      |> Jason.decode!()
      |> Geo.JSON.decode!()

    Map.put(geom, :srid, srid_for(geom))
  end

  # WGS-84 srid by coordinate dimensionality: 4979 when a third ordinate is
  # present (3D / `%Geo.*Z{}`), 4326 otherwise.
  defp srid_for(%{coordinates: coords}) do
    if coord_dim(coords) == 3, do: @wgs_84_3d, else: @wgs_84_2d
  end

  defp coord_dim(t) when is_tuple(t), do: tuple_size(t)
  defp coord_dim([head | _]), do: coord_dim(head)
  defp coord_dim(_), do: 2

  @doc """
  Derives the RFC 7946 §5 bbox for a geometry as `[west, south, east, north]`
  (2D, WGS-84). Walks the coordinate structure recursively, so works for
  any geometry shape — Point, LineString, Polygon (incl. holes),
  MultiPoint, MultiLineString, MultiPolygon.
  """
  @spec bbox(Geo.geometry()) :: [float()]
  def bbox(%{coordinates: coords}) do
    {min_x, max_x, min_y, max_y} = walk(coords, {nil, nil, nil, nil})
    [min_x, min_y, max_x, max_y]
  end

  # Recursive coordinate walker. Bottoms out on a coordinate tuple — 2D
  # `{x, y}` or 3D `{x, y, z}` (the z ordinate is ignored; the bbox envelope
  # is 2D in this release, even for 3D geometries). Nested lists are walked
  # depth-first.
  defp walk({x, y}, acc), do: acc_xy(x, y, acc)
  defp walk({x, y, _z}, acc), do: acc_xy(x, y, acc)
  defp walk([], acc), do: acc
  defp walk([head | tail], acc), do: walk(tail, walk(head, acc))

  defp acc_xy(x, y, {nil, nil, nil, nil}), do: {x, x, y, y}
  defp acc_xy(x, y, {mn_x, mx_x, mn_y, mx_y}), do: {min(mn_x, x), max(mx_x, x), min(mn_y, y), max(mx_y, y)}
end
