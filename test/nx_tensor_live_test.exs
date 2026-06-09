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
    assert round_trip(:t_default, [1, 2, 3]) |> Nx.to_list() == [1, 2, 3]
    assert round_trip(:t_default, [[1, 2], [3, 4]]) |> Nx.to_list() == [[1, 2], [3, 4]]

    t3 = round_trip(:t_default, [[[1, 2], [3, 4]], [[5, 6], [7, 8]]])
    assert Nx.to_list(t3) == [[[1, 2], [3, 4]], [[5, 6], [7, 8]]]
    assert Nx.shape(t3) == {2, 2, 2}
  end

  test "float (f32) tensor round-trips via native LIST" do
    t = round_trip(:t_f32, [[1.5, 2.5], [3.5, 4.5]])
    assert Nx.to_list(t) == [[1.5, 2.5], [3.5, 4.5]]
    assert Nx.type(t) == {:f, 32}
  end

  test "packed (base64) float tensor round-trips" do
    t = round_trip(:t_packed, [[1.5, 2.5], [3.5, 4.5]])
    assert Nx.to_list(t) == [[1.5, 2.5], [3.5, 4.5]]
    assert Nx.type(t) == {:f, 32}
  end

  test "on-disk shape: outer value + shape sidecar; property is a native LIST, packed is a STRING" do
    created =
      Ash.create!(NxTensor, %{
        t_default: [[1, 2], [3, 4]],
        t_packed: [[1.5, 2.5]]
      })

    assert {:ok, %{records: records}} = Neo4jHelper.read_nodes(:NxTensor, %{uuid: created.uuid})
    node = records |> List.first() |> List.first()
    props = node.properties

    # :property — flat native LIST + shape sidecar (no type sidecar — the
    # element type is the declared constraint, recovered on read).
    assert props["tDefault"] == [1, 2, 3, 4]
    assert props["tDefault.shape"] == [2, 2]
    refute Map.has_key?(props, "tDefault.type")

    # :packed — base64 STRING + shape sidecar
    assert is_binary(props["tPacked"])
    assert props["tPacked.shape"] == [1, 2]
  end
end
