# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.VectorSimilarity do
  @moduledoc """
  Cosine similarity between a stored vector attribute and a query embedding.

  Returns a float in `[-1.0, 1.0]` (1.0 = identical direction). Typically used
  in `order_by` to rank results by relevance.

      Item
      |> Ash.Query.sort(vector_similarity(embedding, ^query_embedding), :desc)
      |> Ash.read!()

  Requires Bolt 6.0 vector support (`policy.vectors` must be `true`). The data
  layer pushes this down to:

      vector.similarity.cosine(s.embedding, $query_embedding)

  In-memory evaluation is not supported — the database does the work.
  """
  use Ash.Query.Function, name: :vector_similarity, predicate?: false

  def args, do: [[:any, :any]]

  def returns, do: [:float]

  def evaluate(_), do: :unknown
end
