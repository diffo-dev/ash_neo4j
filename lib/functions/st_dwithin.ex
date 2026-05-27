# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.StDwithin do
  @moduledoc """
  True if two geometries are within a given distance of each other.
  Mirrors ash_geo / PostGIS `ST_DWithin`. v1 supports point-point only,
  with the threshold in meters (geodesic, WGS-84).

      Place
      |> Ash.Query.filter(st_dwithin(location, ^customer_point, 5_000))
      |> Ash.read!()

  Pushes down to Neo4j's native:

      point.distance(n.location, $test_point) <= $threshold

  …a single boolean predicate. Falls back to in-memory `evaluate/1` if the
  data layer can't push it down. Boundary is inclusive (matches PostGIS
  semantics).
  """
  use Ash.Query.Function, name: :st_dwithin, predicate?: true

  def args, do: [[:any, :any, :any]]

  def returns, do: [:boolean]

  def evaluate(%{arguments: [nil, _, _]}), do: {:known, false}
  def evaluate(%{arguments: [_, nil, _]}), do: {:known, false}
  def evaluate(%{arguments: [_, _, nil]}), do: {:known, false}

  def evaluate(%{arguments: [a, b, threshold]}) when is_number(threshold) do
    case AshNeo4j.Functions.StDistance.evaluate(%{arguments: [a, b]}) do
      {:known, nil} -> {:known, false}
      {:known, distance} when is_number(distance) -> {:known, distance <= threshold}
      other -> other
    end
  end

  def evaluate(_), do: :unknown
end
