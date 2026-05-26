# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Type.LineString do
  @moduledoc """
  Ash type for an open polyline of N WGS-84 2D vertices — a fibre run, a
  road trace, a GPS track. Mirrors the GeoJSON `LineString` primitive.

  Stored on the node as a `LIST<POINT>` of the vertices in order, plus 2
  scalar Point companion properties (`<prop>.bbSW`, `<prop>.bbNE`) for
  indexed bounding-box prefilter. Open shape — no closure assumed, no
  winding constraint.

      attribute :path, AshNeo4j.Type.LineString

      Place |> Ash.create!(%{
        name: "Sydney to Newcastle fibre",
        path: %AshNeo4j.Type.LineString{
          vertices: [
            Bolty.Types.Point.create(:wgs_84, 151.21, -33.87),
            Bolty.Types.Point.create(:wgs_84, 151.30, -33.50),
            Bolty.Types.Point.create(:wgs_84, 151.78, -32.93)
          ]
        }
      })

  A LineString requires at least 2 vertices. See
  [ash_neo4j#271](https://github.com/diffo-dev/ash_neo4j/issues/271).
  """
  use Ash.Type

  defstruct vertices: []

  @type t :: %__MODULE__{vertices: [Bolty.Types.Point.t()]}

  @wgs_84_2d 4326

  @impl true
  def storage_type(_constraints), do: :line_string

  @impl true
  def cast_input(nil, _constraints), do: {:ok, nil}

  def cast_input(%__MODULE__{vertices: vertices} = ls, _constraints) when is_list(vertices) and length(vertices) >= 2 do
    case Enum.find(vertices, &(not match?(%Bolty.Types.Point{srid: @wgs_84_2d}, &1))) do
      nil -> {:ok, ls}
      bad -> {:error, "AshNeo4j.Type.LineString vertices must all be WGS-84 2D %Bolty.Types.Point{}; got #{inspect(bad)}"}
    end
  end

  def cast_input(%__MODULE__{vertices: vertices}, _constraints) when is_list(vertices) do
    {:error, "AshNeo4j.Type.LineString requires at least 2 vertices; got #{length(vertices)}"}
  end

  def cast_input(value, _constraints) do
    {:error, "AshNeo4j.Type.LineString expects a %AshNeo4j.Type.LineString{vertices: [...]}; got #{inspect(value)}"}
  end

  @impl true
  def cast_stored(nil, _constraints), do: {:ok, nil}

  def cast_stored(vertices, _constraints) when is_list(vertices) and length(vertices) >= 2 do
    if Enum.all?(vertices, &match?(%Bolty.Types.Point{srid: @wgs_84_2d}, &1)) do
      {:ok, %__MODULE__{vertices: vertices}}
    else
      {:error, "AshNeo4j.Type.LineString cannot load vertex list containing non-WGS-84-2D points: #{inspect(vertices)}"}
    end
  end

  def cast_stored(value, _constraints) do
    {:error, "AshNeo4j.Type.LineString cannot load #{inspect(value)} from storage"}
  end

  @impl true
  def dump_to_native(nil, _constraints), do: {:ok, nil}

  def dump_to_native(%__MODULE__{vertices: vertices}, _constraints) when is_list(vertices) do
    {:ok, vertices}
  end

  def dump_to_native(value, _constraints) do
    {:error, "AshNeo4j.Type.LineString cannot dump #{inspect(value)}"}
  end

  @doc """
  Derives the 2 scalar bbox companion properties (`bbSW`, `bbNE`) from a
  dumped vertex array — min/max over all vertex coordinates. Called by the
  data layer's runtime property assembly to write companions alongside the
  main vertex array for indexed bounding-box prefilter.
  """
  def companions(vertices) when is_list(vertices) and length(vertices) >= 2 do
    {min_x, max_x} = vertices |> Enum.map(& &1.x) |> Enum.min_max()
    {min_y, max_y} = vertices |> Enum.map(& &1.y) |> Enum.min_max()

    %{
      "bbSW" => Bolty.Types.Point.create(:wgs_84, min_x, min_y),
      "bbNE" => Bolty.Types.Point.create(:wgs_84, max_x, max_y)
    }
  end
end
