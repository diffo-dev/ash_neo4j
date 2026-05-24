# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Type.Box do
  @moduledoc """
  Ash type for an axis-aligned bounding box. v1 supports WGS-84 2D only.

  A Box is two `%Bolty.Types.Point{}` corners — `sw` (south-west, lower-left)
  and `ne` (north-east, upper-right) — matching Neo4j's `point.withinBBox`
  signature exactly.

  Stored on the node as a 4-Point vertex array `[sw, se, ne, nw]` (CCW from
  SW per GeoJSON convention), plus 4 scalar Point companion properties
  (`<prop>.bbSW`, `<prop>.bbSE`, `<prop>.bbNE`, `<prop>.bbNW`) written by
  the data layer for indexed bounding-box queries. The same on-disk shape
  will be used by `AshNeo4j.Type.Polygon` when it lands — a Box is a
  4-vertex straight-sided polygon that happens to be axis-aligned. No
  data migration when Polygon ships.

      attribute :bounds, AshNeo4j.Type.Box

      Place |> Ash.create!(%{
        name: "Sydney bbox",
        bounds: %AshNeo4j.Type.Box{
          sw: Bolty.Types.Point.create(:wgs_84, 151.0, -34.0),
          ne: Bolty.Types.Point.create(:wgs_84, 151.5, -33.5)
        }
      })

  Antimeridian-crossing boxes (where `sw.x > ne.x`) are rejected in v1.
  See [ash_neo4j#45](https://github.com/diffo-dev/ash_neo4j/issues/45).
  """
  use Ash.Type

  defstruct sw: nil, ne: nil

  @type t :: %__MODULE__{sw: Bolty.Types.Point.t(), ne: Bolty.Types.Point.t()}

  @wgs_84_2d 4326

  @impl true
  def storage_type(_constraints), do: :box

  @impl true
  def cast_input(nil, _constraints), do: {:ok, nil}

  def cast_input(%__MODULE__{sw: %Bolty.Types.Point{srid: @wgs_84_2d} = sw, ne: %Bolty.Types.Point{srid: @wgs_84_2d} = ne} = box, _constraints) do
    cond do
      sw.x > ne.x ->
        {:error, "AshNeo4j.Type.Box v1 rejects antimeridian-crossing boxes; sw.x (#{sw.x}) > ne.x (#{ne.x})"}

      sw.y > ne.y ->
        {:error, "AshNeo4j.Type.Box requires sw.y ≤ ne.y; got sw.y #{sw.y} > ne.y #{ne.y}"}

      true ->
        {:ok, box}
    end
  end

  def cast_input(%__MODULE__{sw: %Bolty.Types.Point{srid: srid}}, _constraints) when srid != @wgs_84_2d do
    {:error, "AshNeo4j.Type.Box.sw must be WGS-84 2D (srid 4326); got srid #{srid}"}
  end

  def cast_input(%__MODULE__{ne: %Bolty.Types.Point{srid: srid}}, _constraints) when srid != @wgs_84_2d do
    {:error, "AshNeo4j.Type.Box.ne must be WGS-84 2D (srid 4326); got srid #{srid}"}
  end

  def cast_input(value, _constraints) do
    {:error, "AshNeo4j.Type.Box expects a %AshNeo4j.Type.Box{} with sw and ne %Bolty.Types.Point{} corners; got #{inspect(value)}"}
  end

  @impl true
  def cast_stored(nil, _constraints), do: {:ok, nil}

  def cast_stored(
        [
          %Bolty.Types.Point{srid: @wgs_84_2d} = sw,
          %Bolty.Types.Point{srid: @wgs_84_2d} = se,
          %Bolty.Types.Point{srid: @wgs_84_2d} = ne,
          %Bolty.Types.Point{srid: @wgs_84_2d} = nw
        ],
        _constraints
      ) do
    if sw.x == nw.x and ne.x == se.x and sw.y == se.y and ne.y == nw.y do
      {:ok, %__MODULE__{sw: sw, ne: ne}}
    else
      {:error, "AshNeo4j.Type.Box cannot load non-straight-sided 4-point array as a Box: #{inspect([sw, se, ne, nw])}"}
    end
  end

  def cast_stored(value, _constraints) do
    {:error, "AshNeo4j.Type.Box cannot load #{inspect(value)} from storage"}
  end

  @impl true
  def dump_to_native(nil, _constraints), do: {:ok, nil}

  def dump_to_native(%__MODULE__{sw: %Bolty.Types.Point{} = sw, ne: %Bolty.Types.Point{} = ne}, _constraints) do
    se = Bolty.Types.Point.create(:wgs_84, ne.x, sw.y)
    nw = Bolty.Types.Point.create(:wgs_84, sw.x, ne.y)
    {:ok, [sw, se, ne, nw]}
  end

  def dump_to_native(value, _constraints) do
    {:error, "AshNeo4j.Type.Box cannot dump #{inspect(value)}"}
  end

  @doc """
  Derives the 4 scalar bbox companion properties (`bbSW`, `bbSE`, `bbNE`, `bbNW`)
  from a dumped 4-Point array. Called by the data layer's runtime property
  assembly to write companion properties alongside the main vertex array.
  Same shape that Polygon will use — for Box the companions are the polygon
  vertices themselves.
  """
  def companions([%Bolty.Types.Point{} = sw, %Bolty.Types.Point{} = se, %Bolty.Types.Point{} = ne, %Bolty.Types.Point{} = nw]) do
    %{"bbSW" => sw, "bbSE" => se, "bbNE" => ne, "bbNW" => nw}
  end
end
