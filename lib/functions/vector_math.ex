# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.VectorMath do
  @moduledoc """
  Shared in-memory cosine maths for the vector query functions.

  Used by `evaluate/1` in `AshNeo4j.Functions.VectorSimilarity` and
  `AshNeo4j.Functions.VectorCosineDistance` so the data layer's in-memory
  correctness re-filter (`Ash.Filter.Runtime`) produces the same values as the
  Cypher pushdown. Neo4j normalises cosine similarity to `[0, 1]` as
  `(1 + raw_cosine) / 2`; the callers derive their results from `raw_cosine/2`
  accordingly.
  """

  @doc "True when `a` and `b` are equal-length, non-empty numeric lists."
  def comparable_vectors?(a, b) do
    is_list(a) and is_list(b) and a != [] and length(a) == length(b) and
      Enum.all?(a, &is_number/1) and Enum.all?(b, &is_number/1)
  end

  @doc """
  Raw cosine similarity in `[-1.0, 1.0]` — `dot(a, b) / (‖a‖ · ‖b‖)`.

  Returns `0.0` if either vector has zero magnitude. Assumes
  `comparable_vectors?/2` already held.
  """
  def raw_cosine(a, b) do
    dot = a |> Enum.zip(b) |> Enum.reduce(0.0, fn {x, y}, acc -> acc + x * y end)
    mag_a = :math.sqrt(Enum.reduce(a, 0.0, fn x, acc -> acc + x * x end))
    mag_b = :math.sqrt(Enum.reduce(b, 0.0, fn x, acc -> acc + x * x end))

    if mag_a == 0.0 or mag_b == 0.0, do: 0.0, else: dot / (mag_a * mag_b)
  end
end
