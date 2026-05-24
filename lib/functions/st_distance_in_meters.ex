# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.StDistanceInMeters do
  @moduledoc """
  Alias for `st_distance`. PostGIS distinguishes the two because PostGIS
  `ST_Distance` returns degrees for geographic types unless cast; Neo4j's
  `point.distance` is always meters for WGS-84, so the distinction is
  cosmetic for us. This module exists for API parity with ash_geo so
  consumer code reads identically across data layers.

      Place
      |> Ash.Query.filter(st_distance_in_meters(location, ^p) < 5_000)
      |> Ash.read!()

  Same pushdown shape as `st_distance` — the comparison renders to
  `point.distance(n.<prop>, $test) <op> $threshold`. `evaluate/1` delegates.
  """
  use Ash.Query.Function, name: :st_distance_in_meters, predicate?: false

  def args, do: [[:any, :any]]

  def returns, do: [:float]

  def evaluate(args), do: AshNeo4j.Functions.StDistance.evaluate(args)
end
