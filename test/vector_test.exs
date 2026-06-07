# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.VectorTest do
  @moduledoc """
  Pure `AshNeo4j.Vector.index_statements/3` dry-run tests — no Neo4j connection.

  Live vector search and index-lifecycle tests are in
  `AshNeo4j.VectorSearchTest` (tagged `:cypher25`).
  """
  use ExUnit.Case, async: true

  alias AshNeo4j.Test.Resource.ThingNote
  alias AshNeo4j.Vector

  describe "index_statements/3 (dry run, no connection)" do
    test "renders CREATE VECTOR INDEX for a vector attribute" do
      assert {:ok, cypher} = Vector.index_statements(ThingNote, :embedding)

      assert cypher ==
               "CREATE VECTOR INDEX thingnote_embedding_vector IF NOT EXISTS " <>
                 "FOR (n:ThingNote) ON (n.embedding) " <>
                 "OPTIONS {indexConfig: {`vector.dimensions`: 3, `vector.similarity_function`: 'cosine'}}"
    end

    test "honours the :similarity_function option" do
      assert {:ok, cypher} = Vector.index_statements(ThingNote, :embedding, similarity_function: :euclidean)
      assert cypher =~ "'euclidean'"
    end

    test "errors when the attribute is not AshNeo4j.Types.Vector" do
      assert {:error, msg} = Vector.index_statements(ThingNote, :body)
      assert msg =~ "not AshNeo4j.Types.Vector"
    end
  end
end

defmodule AshNeo4j.VectorSearchTest do
  @moduledoc """
  Live vector search and index lifecycle (#74).

  Tagged `:cypher25` and `async: false`: these need a Cypher 25 server
  (Neo4j ≥ 2025.06), provided by the `Bolt6` pool (Neo4j 2026.05), which they
  route to via the process-scoped pool override. Embeddings are stored and
  queried as `LIST<FLOAT>`, so similarity search does not actually require Bolt
  6.0 — Cypher 25 is the only requirement. Each `Sandbox.checkout/0` holds a
  transaction on that small pool, so they run serially. Cosine
  similarity/distance is a plain Cypher function and needs no vector index, so
  the search tests run inside the sandbox transaction.
  """
  use ExUnit.Case, async: false

  require Ash.Query
  import Ash.Expr

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.ThingNote
  alias AshNeo4j.Vector

  describe "vector search" do
    @describetag :cypher25

    setup do
      Process.put(:ash_neo4j_pool, Bolt6)
      Sandbox.checkout()
      on_exit(&Sandbox.rollback/0)
      :ok
    end

    # Three notes spread around the query direction [1,0,0]:
    #   a → identical (similarity 1.0, distance 0.0)
    #   b → orthogonal (similarity 0.5, distance 1.0)
    #   c → opposite   (similarity 0.0, distance 2.0)
    defp seed_notes do
      a = ThingNote |> Ash.create!(%{body: "a", embedding: [1.0, 0.0, 0.0]})
      b = ThingNote |> Ash.create!(%{body: "b", embedding: [0.0, 1.0, 0.0]})
      c = ThingNote |> Ash.create!(%{body: "c", embedding: [-1.0, 0.0, 0.0]})
      {a, b, c}
    end

    test "round-trips a vector property as a float list" do
      note = ThingNote |> Ash.create!(%{body: "rt", embedding: [1.0, 2.0, 3.0]})
      reloaded = ThingNote |> Ash.get!(note.id)
      assert reloaded.embedding == [1.0, 2.0, 3.0]
    end

    test "filters by vector_cosine_distance threshold" do
      {a, b, _c} = seed_notes()
      q = [1.0, 0.0, 0.0]

      {:ok, results} =
        ThingNote
        |> Ash.Query.filter(vector_cosine_distance(embedding, ^q) < 1.5)
        |> Ash.read()

      ids = MapSet.new(results, & &1.id)
      # a (0.0) and b (1.0) are within 1.5; c (2.0) is excluded.
      assert MapSet.new([a.id, b.id]) == ids
    end

    test "sorts by vector_cosine_distance ascending (closest first)" do
      {a, b, c} = seed_notes()
      q = [1.0, 0.0, 0.0]

      {:ok, results} =
        ThingNote
        |> Ash.Query.sort({calc(vector_cosine_distance(embedding, ^q), type: :float), :asc})
        |> Ash.read()

      assert Enum.map(results, & &1.id) == [a.id, b.id, c.id]
    end

    test "sorts by vector_similarity descending (closest first)" do
      {a, b, c} = seed_notes()
      q = [1.0, 0.0, 0.0]

      {:ok, results} =
        ThingNote
        |> Ash.Query.sort({calc(vector_similarity(embedding, ^q), type: :float), :desc})
        |> Ash.read()

      assert Enum.map(results, & &1.id) == [a.id, b.id, c.id]
    end

    test "sort + limit returns the top-k nearest" do
      {a, b, _c} = seed_notes()
      q = [1.0, 0.0, 0.0]

      {:ok, results} =
        ThingNote
        |> Ash.Query.sort({calc(vector_cosine_distance(embedding, ^q), type: :float), :asc})
        |> Ash.Query.limit(2)
        |> Ash.read()

      assert Enum.map(results, & &1.id) == [a.id, b.id]
    end
  end

  describe "index lifecycle (live)" do
    @describetag :cypher25

    setup do
      # No sandbox: CREATE/DROP INDEX is a schema op and cannot share an explicit
      # data transaction. Route to Bolt6 and clean up the index explicitly.
      Process.put(:ash_neo4j_pool, Bolt6)
      # on_exit runs in a separate process without the pool override — set it there too.
      on_exit(fn -> BoltyHelper.with_pool(Bolt6, fn -> Vector.drop_index(ThingNote, :embedding) end) end)
      :ok
    end

    test "create_index/3 then drop_index/3 succeed against the live server" do
      assert {:ok, _} = Vector.create_index(ThingNote, :embedding)
      # idempotent — IF NOT EXISTS
      assert {:ok, _} = Vector.create_index(ThingNote, :embedding)
      assert {:ok, _} = Vector.drop_index(ThingNote, :embedding)
    end
  end
end
