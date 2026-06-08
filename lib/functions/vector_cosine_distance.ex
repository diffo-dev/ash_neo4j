# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.VectorCosineDistance do
  @moduledoc """
  Cosine *distance* between a stored vector attribute and a query embedding —
  the ash_ai-compatible counterpart to `AshNeo4j.Functions.VectorSimilarity`.

  Returns a float in `[0.0, 2.0]` where `0.0` is identical direction and larger
  is further apart (lower = closer). This matches pgvector's `<=>` operator
  (`vector_cosine_distance` in ash_ai), so the same `read` action expression —

      Ash.Query.filter(query, vector_cosine_distance(embedding, ^q) < 0.5)
      |> Ash.Query.sort({calc(vector_cosine_distance(embedding, ^q), type: :float), :asc})
      |> Ash.Query.limit(10)

  — works against AshNeo4j and AshPostgres alike.

  Neo4j's `vector.similarity.cosine/2` returns a *normalised similarity* in
  `[0.0, 1.0]` (`1.0` identical, `0.5` orthogonal, `0.0` opposite). The data
  layer maps it back to pgvector-style distance as `2 * (1 - similarity)`.

  Requires Cypher 25 (Neo4j ≥ 2025.06). The data layer pushes this down to
  `2 * (1 - vector.similarity.cosine(s.embedding, $q))`. `evaluate/1` mirrors
  that exact maths in Elixir (`1 - raw_cosine`) so the data layer's in-memory
  correctness re-filter agrees with the pushdown.
  """
  use Ash.Query.Function, name: :vector_cosine_distance, predicate?: false

  import AshNeo4j.Functions.VectorMath, only: [raw_cosine: 2, comparable_vectors?: 2]

  def args, do: [[:any, :any]]

  def returns, do: [:float]

  def evaluate(%{arguments: [a, b]}) do
    if comparable_vectors?(a, b) do
      {:known, 1.0 - raw_cosine(a, b)}
    else
      {:known, nil}
    end
  end
end
