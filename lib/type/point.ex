# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Type.Point do
  @moduledoc """
  Ash type for a WGS-84 2D point. v2 surface — see
  [#274](https://github.com/diffo-dev/ash_neo4j/issues/274).

  Wraps `%Geo.Point{coordinates: {lng, lat}, srid: 4326}` — the canonical
  Elixir spatial library type. `Bolty.Types.Point` no longer appears at
  the Ash boundary.

      attribute :location, AshNeo4j.Type.Point

      Place |> Ash.create!(%{
        name: "Sydney CBD",
        location: %Geo.Point{coordinates: {151.2093, -33.8688}, srid: 4326}
      })

  ## On-disk shape — symmetric split

  A Point attribute splits into **two suffixed properties on the node**:

    - `<attr>.point` — native Neo4j `POINT` (primary; preserves server-side
      `point.distance` and `point.withinBBox` pushdown).
    - `<attr>.json` — RFC 7946 GeoJSON `STRING` companion (self-describing
      sidecar; any GIS tool can ingest the string directly).

  Nothing is stored at the bare `<attr>` key. Every property's role is in
  its suffix — the same principle as the `bbSW`/`bbNE` companions used by
  other geometry types, just extended to the primary value as well.

  ## Breaking change from v0.7.0

  v0.7.0 accepted/returned `%Bolty.Types.Point{}` and stored the native
  Point at `<attr>`. v2 accepts/returns `%Geo.Point{}` and writes
  `<attr>.point` + `<attr>.json` instead. Existing 0.7.0 Point-bearing
  nodes will need re-creation or a one-shot migration cypher to move
  data from `location` → `location.point` and add `location.json`.
  """
  use Ash.Type

  alias AshNeo4j.GeoJson

  @wgs_84_2d 4326

  @impl true
  def storage_type(_constraints), do: :point

  @doc """
  Declares that this type's primary stored value lives at `<attr>.point`
  rather than the bare `<attr>` key. Read by the data layer's
  `dump_properties/2` (for writes) and `primary_property_key/3` (for
  reads). Other geometry types may declare their own `primary_suffix/0`
  to opt into the symmetric-split pattern.
  """
  def primary_suffix, do: "point"

  @impl true
  def cast_input(nil, _constraints), do: {:ok, nil}

  def cast_input(%Geo.Point{srid: @wgs_84_2d, coordinates: {x, y}} = pt, _constraints)
      when is_number(x) and is_number(y) do
    {:ok, pt}
  end

  def cast_input(%Geo.Point{srid: srid}, _constraints) do
    {:error, "AshNeo4j.Type.Point requires WGS-84 2D (srid 4326); got srid #{inspect(srid)}"}
  end

  def cast_input(value, _constraints) do
    {:error, "AshNeo4j.Type.Point expects a %Geo.Point{coordinates: {lng, lat}, srid: 4326}; got #{inspect(value)}"}
  end

  @impl true
  def cast_stored(nil, _constraints), do: {:ok, nil}

  def cast_stored(%Bolty.Types.Point{srid: @wgs_84_2d, x: x, y: y}, _constraints) do
    {:ok, %Geo.Point{coordinates: {x, y}, srid: @wgs_84_2d}}
  end

  def cast_stored(value, _constraints) do
    {:error, "AshNeo4j.Type.Point cannot load #{inspect(value)} from storage"}
  end

  @impl true
  def dump_to_native(nil, _constraints), do: {:ok, nil}

  def dump_to_native(%Geo.Point{srid: @wgs_84_2d, coordinates: {x, y}}, _constraints) do
    {:ok, Bolty.Types.Point.create(:wgs_84, x, y)}
  end

  def dump_to_native(value, _constraints) do
    {:error, "AshNeo4j.Type.Point cannot dump #{inspect(value)}"}
  end

  @doc """
  Derives the `<attr>.json` companion (RFC 7946 GeoJSON STRING) from a
  dumped native `%Bolty.Types.Point{}`. The companion is written
  alongside the primary `<attr>.point` so the on-disk node is
  self-describing for GIS-tool ingestion.
  """
  def companions(%Bolty.Types.Point{x: x, y: y}) do
    %{"json" => GeoJson.encode!(%Geo.Point{coordinates: {x, y}, srid: @wgs_84_2d})}
  end
end
