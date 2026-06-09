# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.NestedArrayTest do
  @moduledoc false
  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Neo4jHelper
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.NestedArray

  use ExUnit.Case, async: true

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  # Round-trips a single nested-array attribute and asserts the read value
  # matches what went in.
  defp round_trip(attr, value) do
    created = Ash.create!(NestedArray, %{attr => value})
    read = Ash.get!(NestedArray, created.uuid)
    Map.get(read, attr)
  end

  test "2-level native groups round-trip" do
    assert round_trip(:aa_integer, [[1, 2], [3, 4]]) == [[1, 2], [3, 4]]
    assert round_trip(:aa_float, [[1.5, 2.5], [3.5]]) == [[1.5, 2.5], [3.5]]
    assert round_trip(:aa_boolean, [[true, false], [false]]) == [[true, false], [false]]
    assert round_trip(:aa_string, [["a", "b"], ["c"]]) == [["a", "b"], ["c"]]
  end

  test "2-level atom (ash) round-trips" do
    assert round_trip(:aa_atom, [[:a, :b], [:c]]) == [[:a, :b], [:c]]
  end

  test "2-level binary (base64) round-trips" do
    assert round_trip(:aa_binary, [[<<1, 2>>, <<3>>], [<<4, 5, 6>>]]) == [[<<1, 2>>, <<3>>], [<<4, 5, 6>>]]
  end

  test "2-level embedded-json (map) round-trips" do
    v = [[%{name: "Henry", age: 8, breed: :groodle}], [%{name: "Kipper", age: 15, breed: :labradoodle}]]
    assert round_trip(:aa_map, v) == v
  end

  test "2-level temporal (date) round-trips" do
    assert round_trip(:aa_date, [[~D[2025-05-11], ~D[2025-05-12]], [~D[2026-01-01]]]) ==
             [[~D[2025-05-11], ~D[2025-05-12]], [~D[2026-01-01]]]
  end

  test "2-level temporal (duration) round-trips" do
    d = %Duration{day: 25, hour: 5, minute: 6, second: 7}
    assert round_trip(:aa_duration, [[d]]) == [[d]]
  end

  test "3-level integer round-trips" do
    v = [[[1, 2], [3, 4]], [[5, 6], [7, 8]]]
    assert round_trip(:aaa_integer, v) == v
  end

  test "on-disk shape: outer native LIST of (clean) JSON strings, not collections-of-collections" do
    created =
      Ash.create!(NestedArray, %{
        aa_integer: [[1, 2], [3, 4]],
        aa_map: [[%{name: "Henry", age: 8, breed: :groodle}]]
      })

    assert {:ok, %{records: records}} = Neo4jHelper.read_nodes(:NestedArray, %{uuid: created.uuid})
    node = records |> List.first() |> List.first()

    # Outer axis is a native Neo4j LIST; each element is a JSON STRING.
    assert node.properties["aaInteger"] == ["[1,2]", "[3,4]"]

    # The map leaf is clean nested JSON (decodes straight to a map), not a
    # double-escaped string.
    assert [json] = node.properties["aaMap"]
    assert {:ok, [%{"name" => "Henry", "age" => 8, "breed" => "groodle"}]} = Jason.decode(json)
  end
end
