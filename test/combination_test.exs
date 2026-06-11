# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.CombinationTest do
  @moduledoc """
  End-to-end tests for `Ash.Query.combination_of` through the AshNeo4j data layer.
  v1 covers native UNION / UNION ALL pushdown via `CALL { … UNION/UNION ALL … }`
  blocks. INTERSECT / EXCEPT are advertised in `can?/2` but not yet implemented —
  the data layer returns an error for those (in-memory implementation is the next slice).
  """
  use ExUnit.Case, async: true

  require Ash.Expr
  import Ash.Expr

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Author

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  describe "native pushdown — UNION and UNION ALL" do
    test "UNION ALL of two non-overlapping branches returns both authors" do
      alice = Author |> Ash.create!(%{name: "Alice"})
      bob = Author |> Ash.create!(%{name: "Bob"})
      _charlie = Author |> Ash.create!(%{name: "Charlie"})

      {:ok, results} =
        Author
        |> Ash.Query.combination_of([
          Ash.Query.Combination.base(filter: expr(name == "Alice")),
          Ash.Query.Combination.union_all(filter: expr(name == "Bob"))
        ])
        |> Ash.read()

      ids = Enum.map(results, & &1.id)
      assert alice.id in ids
      assert bob.id in ids
      assert length(results) == 2
    end

    test "UNION (deduplicated) of overlapping branches returns the unique record" do
      alice = Author |> Ash.create!(%{name: "Alice"})

      {:ok, results} =
        Author
        |> Ash.Query.combination_of([
          Ash.Query.Combination.base(filter: expr(name == "Alice")),
          Ash.Query.Combination.union(filter: expr(contains(name, "Ali")))
        ])
        |> Ash.read()

      ids = Enum.map(results, & &1.id)
      assert Enum.count(ids, &(&1 == alice.id)) == 1
    end

    test "UNION ALL of overlapping branches collapses duplicates at the Ash record level" do
      # At the Cypher level, UNION ALL keeps duplicates (verified in cypher_test.exs).
      # At the Ash record level, AshNeo4j's consolidate_groups groups by source node,
      # so two cypher rows for the same Alice collapse into one Ash record. UNION
      # and UNION ALL therefore look identical at the record level for overlapping
      # branches; the difference is only observable at the cypher layer.
      alice = Author |> Ash.create!(%{name: "Alice"})

      {:ok, results} =
        Author
        |> Ash.Query.combination_of([
          Ash.Query.Combination.base(filter: expr(name == "Alice")),
          Ash.Query.Combination.union_all(filter: expr(contains(name, "Ali")))
        ])
        |> Ash.read()

      ids = Enum.map(results, & &1.id)
      assert Enum.count(ids, &(&1 == alice.id)) == 1
    end
  end

  describe "in-memory orchestration — INTERSECT, EXCEPT, mixed" do
    test ":base + :intersect returns the intersection" do
      alice = Author |> Ash.create!(%{name: "Alice"})
      bob = Author |> Ash.create!(%{name: "Bob"})

      {:ok, results} =
        Author
        |> Ash.Query.combination_of([
          Ash.Query.Combination.base(filter: expr(name == "Alice" or name == "Bob")),
          Ash.Query.Combination.intersect(filter: expr(name == "Alice"))
        ])
        |> Ash.read()

      ids = Enum.map(results, & &1.id)
      assert alice.id in ids
      refute bob.id in ids
      assert length(results) == 1
    end

    test ":base + :except returns the set difference" do
      alice = Author |> Ash.create!(%{name: "Alice"})
      bob = Author |> Ash.create!(%{name: "Bob"})

      {:ok, results} =
        Author
        |> Ash.Query.combination_of([
          Ash.Query.Combination.base(filter: expr(name == "Alice" or name == "Bob")),
          Ash.Query.Combination.except(filter: expr(name == "Alice"))
        ])
        |> Ash.read()

      ids = Enum.map(results, & &1.id)
      refute alice.id in ids
      assert bob.id in ids
      assert length(results) == 1
    end

    test ":except where the negative branch removes everything returns empty" do
      _alice = Author |> Ash.create!(%{name: "Alice"})

      {:ok, results} =
        Author
        |> Ash.Query.combination_of([
          Ash.Query.Combination.base(filter: expr(name == "Alice")),
          Ash.Query.Combination.except(filter: expr(contains(name, "A")))
        ])
        |> Ash.read()

      assert results == []
    end

    test "mixed types are applied in order — :base + :union + :except" do
      alice = Author |> Ash.create!(%{name: "Alice"})
      bob = Author |> Ash.create!(%{name: "Bob"})
      _charlie = Author |> Ash.create!(%{name: "Charlie"})

      # base: Alice
      # union: Bob → Alice + Bob
      # except: Alice → Bob
      {:ok, results} =
        Author
        |> Ash.Query.combination_of([
          Ash.Query.Combination.base(filter: expr(name == "Alice")),
          Ash.Query.Combination.union(filter: expr(name == "Bob")),
          Ash.Query.Combination.except(filter: expr(name == "Alice"))
        ])
        |> Ash.read()

      ids = Enum.map(results, & &1.id)
      refute alice.id in ids
      assert bob.id in ids
      assert length(results) == 1
    end
  end
end

defmodule AshNeo4j.CombinationCypher25Test do
  @moduledoc """
  #299 — on a Cypher 25 server the `CYPHER 25` selector must appear only once,
  at the start of the outer query, never inside the `CALL { … }` block of a
  native combination query. Tagged `:cypher25` / `async: false` (routes to the
  Neo4j 2026.05 `Bolt6` pool; excluded by default).
  """
  use ExUnit.Case, async: false

  import Ash.Expr

  alias AshNeo4j.Cypher
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Author

  @moduletag :cypher25

  setup do
    Process.put(:ash_neo4j_pool, Bolt6)
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
    :ok
  end

  test "UNION ALL combination runs end-to-end against a Cypher 25 server" do
    alice = Author |> Ash.create!(%{name: "Alice"})
    bob = Author |> Ash.create!(%{name: "Bob"})
    _charlie = Author |> Ash.create!(%{name: "Charlie"})

    {:ok, results} =
      Author
      |> Ash.Query.combination_of([
        Ash.Query.Combination.base(filter: expr(name == "Alice")),
        Ash.Query.Combination.union_all(filter: expr(name == "Bob"))
      ])
      |> Ash.read()

    ids = Enum.map(results, & &1.id)
    assert alice.id in ids
    assert bob.id in ids
    assert length(results) == 2
  end

  test "the CYPHER 25 selector appears once, only on the outer query" do
    b0 = Cypher.Query.branch_node_read(:Place, [{"name", :==, "X", false}], param_prefix: "b0_")
    b1 = Cypher.Query.branch_node_read(:Place, [{"name", :==, "Y", false}], param_prefix: "b1_")

    {cypher, _} =
      [b0, b1]
      |> Cypher.Query.combination_block(union_type: :union_all)
      |> Cypher.render()

    # prefix is active (we routed to the Cypher 25 pool)
    assert String.starts_with?(cypher, "CYPHER 25 CALL {")
    # and it appears exactly once — no embedded prefix inside the CALL block
    assert length(String.split(cypher, "CYPHER 25 ")) == 2
  end
end
