# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.NxTensorLiveTest do
  @moduledoc false
  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Neo4jHelper
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.NxTensor

  use ExUnit.Case, async: true

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  defp round_trip(attr, value) do
    created = Ash.create!(NxTensor, %{attr => value})
    read = Ash.get!(NxTensor, created.uuid)
    Map.get(read, attr)
  end

  test "1D / 2D / 3D integer tensors round-trip (values + shape)" do
    assert round_trip(:t_1d, [1, 2, 3]) |> Nx.to_list() == [1, 2, 3]
    assert round_trip(:t_2d, [[1, 2], [3, 4]]) |> Nx.to_list() == [[1, 2], [3, 4]]

    t3 = round_trip(:t_3d, [[[1, 2], [3, 4]], [[5, 6], [7, 8]]])
    assert Nx.to_list(t3) == [[[1, 2], [3, 4]], [[5, 6], [7, 8]]]
    assert Nx.shape(t3) == {2, 2, 2}
  end

  test "float (f32) tensor round-trips via native LIST" do
    t = round_trip(:t_f32, [[1.5, 2.5], [3.5, 4.5]])
    assert Nx.to_list(t) == [[1.5, 2.5], [3.5, 4.5]]
    assert Nx.type(t) == {:f, 32}
  end

  test "packed (base64) float tensor round-trips" do
    t = round_trip(:t_packed, [[1.5, 2.5]])
    assert Nx.to_list(t) == [[1.5, 2.5]]
    assert Nx.type(t) == {:f, 32}
  end

  test "a 9x9 Sudoku grid round-trips as a u8 [9,9] tensor" do
    grid = [
      [5, 3, 0, 0, 7, 0, 0, 0, 0],
      [6, 0, 0, 1, 9, 5, 0, 0, 0],
      [0, 9, 8, 0, 0, 0, 0, 6, 0],
      [8, 0, 0, 0, 6, 0, 0, 0, 3],
      [4, 0, 0, 8, 0, 3, 0, 0, 1],
      [7, 0, 0, 0, 2, 0, 0, 0, 6],
      [0, 6, 0, 0, 0, 0, 2, 8, 0],
      [0, 0, 0, 4, 1, 9, 0, 0, 5],
      [0, 0, 0, 0, 8, 0, 0, 7, 9]
    ]

    t = round_trip(:sudoku, grid)
    assert Nx.shape(t) == {9, 9}
    assert Nx.type(t) == {:u, 8}
    assert Nx.to_list(t) == grid
  end

  test "on-disk: the bare flat value, no sidecar (type/shape are schema)" do
    created = Ash.create!(NxTensor, %{t_2d: [[1, 2], [3, 4]], t_packed: [[1.5, 2.5]]})

    assert {:ok, %{records: records}} = Neo4jHelper.read_nodes(:NxTensor, %{uuid: created.uuid})
    node = records |> List.first() |> List.first()
    props = node.properties

    # :property — a bare native LIST, nothing else
    assert props["t2d"] == [1, 2, 3, 4]
    refute Map.has_key?(props, "t2d.shape")
    refute Map.has_key?(props, "t2d.type")

    # :packed — a bare base64 STRING, nothing else
    assert is_binary(props["tPacked"])
    refute Map.has_key?(props, "tPacked.shape")
  end
end
