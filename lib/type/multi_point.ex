# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Type.MultiPoint do
  @moduledoc """
  Ash type for a bounded collection of N WGS-84 2D points — a candidate
  set treated as a single logical unit (candidate PEs for fibre buildout,
  sensors on a single NTD, building entry points, cluster centroids).
  Mirrors the GeoJSON `MultiPoint` primitive.

  Stored on the node as a `LIST<POINT>`, plus 2 scalar Point companion
  properties (`<prop>.bbSW`, `<prop>.bbNE`) for indexed bounding-box
  prefilter.

      attribute :candidate_pes, AshNeo4j.Type.MultiPoint

      Place |> Ash.create!(%{
        name: "Sydney CSA candidate PEs",
        candidate_pes: %AshNeo4j.Type.MultiPoint{
          points: [
            Bolty.Types.Point.create(:wgs_84, 151.21, -33.87),
            Bolty.Types.Point.create(:wgs_84, 151.30, -33.85),
            Bolty.Types.Point.create(:wgs_84, 151.18, -33.92)
          ]
        }
      })

  A MultiPoint requires at least 1 point. See
  [ash_neo4j#271](https://github.com/diffo-dev/ash_neo4j/issues/271).
  """
  use Ash.Type

  defstruct points: []

  @type t :: %__MODULE__{points: [Bolty.Types.Point.t()]}

  @wgs_84_2d 4326

  @impl true
  def storage_type(_constraints), do: :multi_point

  @impl true
  def cast_input(nil, _constraints), do: {:ok, nil}

  def cast_input(%__MODULE__{points: points} = mp, _constraints) when is_list(points) and length(points) >= 1 do
    case Enum.find(points, &(not match?(%Bolty.Types.Point{srid: @wgs_84_2d}, &1))) do
      nil -> {:ok, mp}
      bad -> {:error, "AshNeo4j.Type.MultiPoint points must all be WGS-84 2D %Bolty.Types.Point{}; got #{inspect(bad)}"}
    end
  end

  def cast_input(%__MODULE__{points: []}, _constraints) do
    {:error, "AshNeo4j.Type.MultiPoint requires at least 1 point; got an empty list"}
  end

  def cast_input(value, _constraints) do
    {:error, "AshNeo4j.Type.MultiPoint expects a %AshNeo4j.Type.MultiPoint{points: [...]}; got #{inspect(value)}"}
  end

  @impl true
  def cast_stored(nil, _constraints), do: {:ok, nil}

  def cast_stored(points, _constraints) when is_list(points) and length(points) >= 1 do
    if Enum.all?(points, &match?(%Bolty.Types.Point{srid: @wgs_84_2d}, &1)) do
      {:ok, %__MODULE__{points: points}}
    else
      {:error, "AshNeo4j.Type.MultiPoint cannot load list containing non-WGS-84-2D points: #{inspect(points)}"}
    end
  end

  def cast_stored(value, _constraints) do
    {:error, "AshNeo4j.Type.MultiPoint cannot load #{inspect(value)} from storage"}
  end

  @impl true
  def dump_to_native(nil, _constraints), do: {:ok, nil}

  def dump_to_native(%__MODULE__{points: points}, _constraints) when is_list(points) do
    {:ok, points}
  end

  def dump_to_native(value, _constraints) do
    {:error, "AshNeo4j.Type.MultiPoint cannot dump #{inspect(value)}"}
  end

  @doc """
  Derives the 2 scalar bbox companion properties (`bbSW`, `bbNE`) from a
  dumped point list — min/max over all coordinates. Same shape as
  `AshNeo4j.Type.LineString`.
  """
  def companions(points) when is_list(points) and length(points) >= 1 do
    {min_x, max_x} = points |> Enum.map(& &1.x) |> Enum.min_max()
    {min_y, max_y} = points |> Enum.map(& &1.y) |> Enum.min_max()

    %{
      "bbSW" => Bolty.Types.Point.create(:wgs_84, min_x, min_y),
      "bbNE" => Bolty.Types.Point.create(:wgs_84, max_x, max_y)
    }
  end
end
