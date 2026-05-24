# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Type.Box do
  @moduledoc """
  Ash type for an axis-aligned bounding box. v1 supports WGS-84 2D only.

  A Box is two `%Bolty.Types.Point{}` corners — `sw` (south-west, lower-left)
  and `ne` (north-east, upper-right) — matching Neo4j's `point.withinBBox`
  signature exactly. Stored on the node as a 2-element array of native Points.

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

  def cast_stored([%Bolty.Types.Point{srid: @wgs_84_2d} = sw, %Bolty.Types.Point{srid: @wgs_84_2d} = ne], _constraints) do
    {:ok, %__MODULE__{sw: sw, ne: ne}}
  end

  def cast_stored(value, _constraints) do
    {:error, "AshNeo4j.Type.Box cannot load #{inspect(value)} from storage"}
  end

  @impl true
  def dump_to_native(nil, _constraints), do: {:ok, nil}

  def dump_to_native(%__MODULE__{sw: %Bolty.Types.Point{} = sw, ne: %Bolty.Types.Point{} = ne}, _constraints) do
    {:ok, [sw, ne]}
  end

  def dump_to_native(value, _constraints) do
    {:error, "AshNeo4j.Type.Box cannot dump #{inspect(value)}"}
  end
end
