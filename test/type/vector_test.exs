# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Type.VectorTest do
  @moduledoc """
  Pure cast/constraint tests for `AshNeo4j.Type.Vector` — no Neo4j connection.

  `dump_to_native/2`'s wire-format choice (native `%Bolty.Types.Vector{}` vs
  plain float list) depends on the negotiated `policy.vectors` and is exercised
  end-to-end in the `:bolt6` integration suite.
  """
  use ExUnit.Case, async: true

  alias AshNeo4j.Type.Vector

  describe "cast_input/2" do
    test "accepts a list of numbers, coercing to floats" do
      assert {:ok, [1.0, 2.0, 3.0]} = Vector.cast_input([1, 2, 3], [])
      assert {:ok, [0.1, 0.2]} = Vector.cast_input([0.1, 0.2], [])
    end

    test "unwraps a %Bolty.Types.Vector{} to a float list" do
      assert {:ok, [1.0, 2.0, 3.0]} =
               Vector.cast_input(%Bolty.Types.Vector{type: :float32, data: [1.0, 2.0, 3.0]}, [])
    end

    test "passes nil through" do
      assert {:ok, nil} = Vector.cast_input(nil, [])
    end

    test "rejects non-numeric elements" do
      assert {:error, _} = Vector.cast_input([1.0, "x", 3.0], [])
    end

    test "rejects non-list, non-vector input" do
      assert {:error, _} = Vector.cast_input("not a vector", [])
    end
  end

  describe "cast_stored/2" do
    test "unwraps a %Bolty.Types.Vector{} (Bolt 6.0 read)" do
      assert {:ok, [1.0, 2.0, 3.0]} =
               Vector.cast_stored(%Bolty.Types.Vector{type: :float32, data: [1.0, 2.0, 3.0]}, [])
    end

    test "accepts a plain float list (Bolt 5.x read)" do
      assert {:ok, [1.0, 2.0, 3.0]} = Vector.cast_stored([1.0, 2.0, 3.0], [])
    end

    test "passes nil through" do
      assert {:ok, nil} = Vector.cast_stored(nil, [])
    end
  end

  describe "apply_constraints/2" do
    test "accepts a vector of the declared dimensions" do
      assert {:ok, [1.0, 2.0, 3.0]} = Vector.apply_constraints([1.0, 2.0, 3.0], dimensions: 3)
    end

    test "rejects a dimension mismatch" do
      assert {:error, msg} = Vector.apply_constraints([1.0, 2.0], dimensions: 3)
      assert msg =~ "expected 3 dimensions"
    end

    test "skips the dimension check when no :dimensions constraint is set" do
      assert {:ok, [1.0, 2.0, 3.0]} = Vector.apply_constraints([1.0, 2.0, 3.0], [])
    end
  end

  describe "storage_type/1" do
    test "is :string" do
      assert Vector.storage_type([]) == :string
    end
  end
end
