# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Type.Point do
  @moduledoc """
  Ash type for a Neo4j Point. v1 supports WGS-84 2D only.

  Wraps `Bolty.Types.Point` — values persist as native Neo4j Point properties
  via bolty's PackStream Point packer.

      attribute :location, AshNeo4j.Type.Point

      Place |> Ash.create!(%{
        name: "Sydney CBD",
        location: Bolty.Types.Point.create(:wgs_84, 151.2093, -33.8688)
      })

  See [ash_neo4j#45](https://github.com/diffo-dev/ash_neo4j/issues/45) for the v1 scope
  and future CRSs (Cartesian 2D/3D, WGS-84 3D).
  """
  use Ash.Type

  @wgs_84_2d 4326

  @impl true
  def storage_type(_constraints), do: :point

  @impl true
  def cast_input(nil, _constraints), do: {:ok, nil}

  def cast_input(%Bolty.Types.Point{srid: @wgs_84_2d} = point, _constraints) do
    {:ok, point}
  end

  def cast_input(%Bolty.Types.Point{srid: srid}, _constraints) do
    {:error, "AshNeo4j.Type.Point v1 supports WGS-84 2D (srid 4326) only; got srid #{srid}"}
  end

  def cast_input(value, _constraints) do
    {:error, "AshNeo4j.Type.Point expects a %Bolty.Types.Point{}; got #{inspect(value)}"}
  end

  @impl true
  def cast_stored(nil, _constraints), do: {:ok, nil}

  def cast_stored(%Bolty.Types.Point{srid: @wgs_84_2d} = point, _constraints) do
    {:ok, point}
  end

  def cast_stored(value, _constraints) do
    {:error, "AshNeo4j.Type.Point cannot load #{inspect(value)} from storage"}
  end

  @impl true
  def dump_to_native(nil, _constraints), do: {:ok, nil}

  def dump_to_native(%Bolty.Types.Point{srid: @wgs_84_2d} = point, _constraints) do
    {:ok, point}
  end

  def dump_to_native(value, _constraints) do
    {:error, "AshNeo4j.Type.Point cannot dump #{inspect(value)}"}
  end
end
