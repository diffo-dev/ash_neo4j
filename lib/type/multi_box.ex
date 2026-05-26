# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Type.MultiBox do
  @moduledoc """
  Ash type for a bounded collection of N axis-aligned bounding boxes —
  the indexable subset of GeoJSON `MultiPolygon`, paired with
  `AshNeo4j.Type.Box` the same way that `Box` pairs with the
  (forthcoming) `Polygon` type. Use it for service areas composed of
  several disjoint sub-regions, administrative boundaries with islands,
  or any multi-region geometry where rectangular sub-regions are good
  enough.

  Stored on the node as a flat 4N-Point vertex array — the constituent
  Boxes concatenated as `[sw0, se0, ne0, nw0, sw1, se1, ne1, nw1, …]` —
  plus 2 scalar Point companion properties (`<prop>.bbSW`, `<prop>.bbNE`)
  covering the **union** bounding box of all constituent boxes. The
  per-box predicates iterate the array in chunks of 4 in Elixir.

      attribute :regions, AshNeo4j.Type.MultiBox

      Place |> Ash.create!(%{
        name: "Sydney CSA carve-outs",
        regions: %AshNeo4j.Type.MultiBox{
          boxes: [
            %AshNeo4j.Type.Box{
              sw: Bolty.Types.Point.create(:wgs_84, 151.0, -34.0),
              ne: Bolty.Types.Point.create(:wgs_84, 151.5, -33.5)
            },
            %AshNeo4j.Type.Box{
              sw: Bolty.Types.Point.create(:wgs_84, 151.6, -33.4),
              ne: Bolty.Types.Point.create(:wgs_84, 152.0, -33.0)
            }
          ]
        }
      })

  A MultiBox requires at least 1 box. See
  [ash_neo4j#271](https://github.com/diffo-dev/ash_neo4j/issues/271).
  """
  use Ash.Type

  defstruct boxes: []

  @type t :: %__MODULE__{boxes: [AshNeo4j.Type.Box.t()]}

  @impl true
  def storage_type(_constraints), do: :multi_box

  @impl true
  def cast_input(nil, _constraints), do: {:ok, nil}

  def cast_input(%__MODULE__{boxes: boxes} = mb, constraints) when is_list(boxes) and length(boxes) >= 1 do
    case validate_all(boxes, constraints) do
      :ok -> {:ok, mb}
      {:error, _} = err -> err
    end
  end

  def cast_input(%__MODULE__{boxes: []}, _constraints) do
    {:error, "AshNeo4j.Type.MultiBox requires at least 1 box; got an empty list"}
  end

  def cast_input(value, _constraints) do
    {:error, "AshNeo4j.Type.MultiBox expects a %AshNeo4j.Type.MultiBox{boxes: [...]}; got #{inspect(value)}"}
  end

  @impl true
  def cast_stored(nil, _constraints), do: {:ok, nil}

  def cast_stored(flat_points, _constraints) when is_list(flat_points) and length(flat_points) >= 4 do
    if rem(length(flat_points), 4) != 0 do
      {:error, "AshNeo4j.Type.MultiBox cannot load a #{length(flat_points)}-point array — expected a multiple of 4"}
    else
      flat_points
      |> Enum.chunk_every(4)
      |> Enum.reduce_while({:ok, []}, fn chunk, {:ok, acc} ->
        case AshNeo4j.Type.Box.cast_stored(chunk, []) do
          {:ok, box} -> {:cont, {:ok, [box | acc]}}
          {:error, _} = err -> {:halt, err}
        end
      end)
      |> case do
        {:ok, boxes} -> {:ok, %__MODULE__{boxes: Enum.reverse(boxes)}}
        {:error, _} = err -> err
      end
    end
  end

  def cast_stored(value, _constraints) do
    {:error, "AshNeo4j.Type.MultiBox cannot load #{inspect(value)} from storage"}
  end

  @impl true
  def dump_to_native(nil, _constraints), do: {:ok, nil}

  def dump_to_native(%__MODULE__{boxes: boxes}, _constraints) when is_list(boxes) do
    boxes
    |> Enum.reduce_while({:ok, []}, fn box, {:ok, acc} ->
      case AshNeo4j.Type.Box.dump_to_native(box, []) do
        {:ok, points} -> {:cont, {:ok, acc ++ points}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  def dump_to_native(value, _constraints) do
    {:error, "AshNeo4j.Type.MultiBox cannot dump #{inspect(value)}"}
  end

  @doc """
  Derives the 2 scalar union-bbox companion properties (`bbSW`, `bbNE`)
  from the dumped flat point array — min/max over every vertex of every
  constituent box.
  """
  def companions(flat_points) when is_list(flat_points) and length(flat_points) >= 4 do
    {min_x, max_x} = flat_points |> Enum.map(& &1.x) |> Enum.min_max()
    {min_y, max_y} = flat_points |> Enum.map(& &1.y) |> Enum.min_max()

    %{
      "bbSW" => Bolty.Types.Point.create(:wgs_84, min_x, min_y),
      "bbNE" => Bolty.Types.Point.create(:wgs_84, max_x, max_y)
    }
  end

  defp validate_all(boxes, constraints) do
    Enum.reduce_while(boxes, :ok, fn box, :ok ->
      case AshNeo4j.Type.Box.cast_input(box, constraints) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, "AshNeo4j.Type.MultiBox.boxes: #{reason}"}}
      end
    end)
  end
end
