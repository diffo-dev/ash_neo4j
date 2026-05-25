# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.StWithin do
  @moduledoc """
  `st_within(a, b)` — true if `a` is contained by `b`. Argument-flipped
  `st_contains`. Mirrors ash_geo / PostGIS `ST_Within`.

      Place
      |> Ash.Query.filter(st_within(location, ^search_box))
      |> Ash.read!()

  `evaluate/1` delegates to `StContains` with arguments swapped. No Cypher
  pushdown in this slice — the predicate evaluates in memory via
  `Ash.Filter.Runtime`. For pushdown shape, use `st_contains(^box, location)`
  directly (the pushdown path expects the container property on the LHS).
  """
  use Ash.Query.Function, name: :st_within, predicate?: true

  def args, do: [[:any, :any]]

  def returns, do: [:boolean]

  def evaluate(%{arguments: [a, b]}) do
    AshNeo4j.Functions.StContains.evaluate(%{arguments: [b, a]})
  end
end
