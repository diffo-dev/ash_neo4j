# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Type.NxTensorTest do
  @moduledoc false
  alias AshNeo4j.Type.NxTensor

  use ExUnit.Case, async: true

  describe "cast_input/2" do
    test "from a nested list, defaulting type to u8" do
      assert {:ok, t} = NxTensor.cast_input([[1, 2, 3], [4, 5, 6]], shape: [2, 3])
      assert Nx.to_list(t) == [[1, 2, 3], [4, 5, 6]]
      assert Nx.type(t) == {:u, 8}
    end

    test "from a flat list, reshaped to the declared shape" do
      assert {:ok, t} = NxTensor.cast_input([1, 2, 3, 4], type: :s64, shape: [2, 2])
      assert Nx.to_list(t) == [[1, 2], [3, 4]]
    end

    test "coerces to the declared type" do
      assert {:ok, t} = NxTensor.cast_input([[1, 2]], type: :f32, shape: [1, 2])
      assert Nx.type(t) == {:f, 32}
      assert Nx.to_list(t) == [[1.0, 2.0]]
    end

    test "passes through an %Nx.Tensor{}" do
      assert {:ok, t} = NxTensor.cast_input(Nx.tensor([1, 2, 3], type: :s64), type: :s64, shape: [3])
      assert Nx.to_list(t) == [1, 2, 3]
    end

    test "errors on a flat/shape element-count mismatch" do
      assert {:error, _} = NxTensor.cast_input([1, 2, 3], shape: [2, 2])
    end

    test "errors on a nested-input/shape mismatch" do
      assert {:error, _} = NxTensor.cast_input([[1, 2], [3, 4]], shape: [4])
    end

    test "errors on rank > 3" do
      assert {:error, _} = NxTensor.cast_input([[[[1]]]], shape: [1, 1, 1, 1])
    end

    test "errors on an unknown element type" do
      assert {:error, _} = NxTensor.cast_input([1, 2], type: :not_a_type, shape: [2])
    end
  end

  describe "dump_storage/2 + cast_stored/2 round-trip (type & shape come from the schema)" do
    test ":property — the stored value is a bare flat LIST" do
      tensor = Nx.tensor([[1, 2, 3], [4, 5, 6]], type: :s32)
      assert NxTensor.dump_storage(tensor, :property) == [1, 2, 3, 4, 5, 6]

      assert {:ok, restored} =
               NxTensor.cast_stored([1, 2, 3, 4, 5, 6], type: :s32, shape: [2, 3], store: :property)

      assert Nx.to_list(restored) == [[1, 2, 3], [4, 5, 6]]
      assert Nx.type(restored) == {:s, 32}
    end

    test "sub-word types (u8/s8) round-trip through both codecs" do
      for {type, store} <- [{:u8, :property}, {:u8, :packed}, {:s8, :property}, {:s8, :packed}] do
        {:ok, tensor} = NxTensor.cast_input([[1, 2], [3, 4]], type: type, shape: [2, 2])
        stored = NxTensor.dump_storage(tensor, store)
        assert {:ok, restored} = NxTensor.cast_stored(stored, type: type, shape: [2, 2], store: store)
        assert Nx.to_list(restored) == [[1, 2], [3, 4]]
        assert Nx.type(restored) == Nx.type(tensor)
      end
    end

    test ":packed of a u8 tensor is one byte per element (the sub-word win)" do
      tensor = Nx.tensor([1, 2, 3, 4, 5, 6], type: :u8)
      stored = NxTensor.dump_storage(tensor, :packed)
      assert byte_size(Base.decode64!(stored)) == 6
    end

    test ":packed — base64 binary preserves f32" do
      tensor = Nx.tensor([[1.5, 2.5], [3.5, 4.5]], type: :f32)
      stored = NxTensor.dump_storage(tensor, :packed)
      assert is_binary(stored)

      assert {:ok, restored} = NxTensor.cast_stored(stored, type: :f32, shape: [2, 2], store: :packed)
      assert Nx.to_list(restored) == [[1.5, 2.5], [3.5, 4.5]]
      assert Nx.type(restored) == {:f, 32}
    end
  end

  describe "structural ops are Nx's (value-blind, #309 acceptance)" do
    test "transpose (lazy), reshape, slice (2D->1D), stack (1D->2D)" do
      {:ok, m} = NxTensor.cast_input([[1, 2, 3], [4, 5, 6]], type: :s64, shape: [2, 3])

      assert m |> Nx.transpose() |> Nx.to_list() == [[1, 4], [2, 5], [3, 6]]
      assert m |> Nx.reshape({3, 2}) |> Nx.to_list() == [[1, 2], [3, 4], [5, 6]]
      assert m[1] |> Nx.to_list() == [4, 5, 6]

      {:ok, a} = NxTensor.cast_input([1, 2], type: :s64, shape: [2])
      {:ok, b} = NxTensor.cast_input([3, 4], type: :s64, shape: [2])
      assert Nx.stack([a, b]) |> Nx.to_list() == [[1, 2], [3, 4]]
    end
  end
end
