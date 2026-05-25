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

  require Ash.Query
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
