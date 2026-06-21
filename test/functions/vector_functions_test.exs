# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.VectorFunctionsTest do
  @moduledoc """
  Pure `evaluate/1` maths for the vector query functions.

  These mirror Neo4j's `vector.similarity.cosine/2` normalisation exactly so the
  data layer's in-memory correctness re-filter agrees with the Cypher pushdown.
  The normalisation is verified against the live server in
  `AshNeo4j.VectorSearchTest`.
  """
  use ExUnit.Case, async: true

  alias AshNeo4j.Functions.VectorCosineDistance, as: Distance
  alias AshNeo4j.Functions.VectorSimilarity, as: Similarity

  defp sim(a, b), do: Similarity.evaluate(%{arguments: [a, b]})
  defp dist(a, b), do: Distance.evaluate(%{arguments: [a, b]})

  describe "VectorSimilarity.evaluate/1 (Neo4j-normalised, [0,1], higher = closer)" do
    test "identical → 1.0, orthogonal → 0.5, opposite → 0.0" do
      assert {:known, 1.0} = sim([1.0, 0.0, 0.0], [1.0, 0.0, 0.0])
      assert {:known, 0.5} = sim([1.0, 0.0, 0.0], [0.0, 1.0, 0.0])
      assert {:known, +0.0} = sim([1.0, 0.0, 0.0], [-1.0, 0.0, 0.0])
    end

    test "is magnitude-invariant" do
      assert {:known, 1.0} = sim([2.0, 0.0, 0.0], [5.0, 0.0, 0.0])
    end

    test "returns nil for incomparable arguments" do
      assert {:known, nil} = sim(nil, [1.0, 2.0])
      assert {:known, nil} = sim([1.0, 2.0], [1.0, 2.0, 3.0])
      assert {:known, nil} = sim([], [])
    end
  end

  describe "VectorCosineDistance.evaluate/1 (pgvector-style, [0,2], lower = closer)" do
    test "identical → 0.0, orthogonal → 1.0, opposite → 2.0" do
      assert {:known, +0.0} = dist([1.0, 0.0, 0.0], [1.0, 0.0, 0.0])
      assert {:known, 1.0} = dist([1.0, 0.0, 0.0], [0.0, 1.0, 0.0])
      assert {:known, 2.0} = dist([1.0, 0.0, 0.0], [-1.0, 0.0, 0.0])
    end

    test "distance and similarity are consistent: distance == 2 * (1 - similarity)" do
      a = [0.3, 0.9, -0.2]
      b = [0.5, 0.1, 0.4]
      {:known, s} = sim(a, b)
      {:known, d} = dist(a, b)
      assert_in_delta d, 2.0 * (1.0 - s), 1.0e-9
    end

    test "returns nil for incomparable arguments" do
      assert {:known, nil} = dist([1.0], nil)
    end
  end
end
