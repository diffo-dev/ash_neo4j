# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.VectorSimilarity do
  @moduledoc """
  Normalised cosine similarity between a stored vector attribute and a query
  embedding, matching Neo4j's `vector.similarity.cosine/2`.

  Returns a float in `[0.0, 1.0]` — `1.0` identical direction, `0.5` orthogonal,
  `0.0` opposite — i.e. `(1 + raw_cosine) / 2`. Higher is closer. Typically used
  in `sort` to rank results by relevance:

      Item
      |> Ash.Query.sort({calc(vector_similarity(embedding, ^q), type: :float), :desc})
      |> Ash.read!()

  Requires Cypher 25 (Neo4j ≥ 2025.06). The data layer pushes this down to
  `vector.similarity.cosine(s.embedding, $q)`. `evaluate/1` mirrors that exact
  normalisation in Elixir so the data layer's in-memory correctness re-filter
  agrees with the pushdown (and so filters/sorts also work without pushdown).
  """
  use Ash.Query.Function, name: :vector_similarity, predicate?: false

  import AshNeo4j.Functions.VectorMath, only: [raw_cosine: 2, comparable_vectors?: 2]

  def args, do: [[:any, :any]]

  def returns, do: [:float]

  def evaluate(%{arguments: [a, b]}) do
    if comparable_vectors?(a, b) do
      {:known, (1.0 + raw_cosine(a, b)) / 2.0}
    else
      {:known, nil}
    end
  end
end
