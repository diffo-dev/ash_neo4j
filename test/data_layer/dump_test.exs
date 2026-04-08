# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.DataLayer.Dump.Test do
  @moduledoc false
  use ExUnit.Case, async: false
  alias AshNeo4j.DataLayer.Dump
  alias AshNeo4j.DataLayer.Cast
  alias AshNeo4j.Test.Struct
  alias AshNeo4j.Test.StructInStruct

  describe "dump native types" do
    test "using Ash.Type alias" do
      value_changed(:atom, :a, "a")
    end

    test "boolean" do
      value_unchanged(Ash.Type.Boolean, true)
    end

    test "string" do
      value_unchanged(Ash.Type.String, "string")
    end

    test "integer" do
      value_unchanged(Ash.Type.Integer, 1)
    end

    test "float" do
      value_unchanged(Ash.Type.Float, 1.0)
    end

    test "date" do
      value_unchanged(Ash.Type.Date, ~D[2025-05-11])
    end

    test "duration" do
      value_unchanged(Ash.Type.Duration, Duration.new!(year: 1))
    end

    test "naive date time" do
      value_unchanged(Ash.Type.NaiveDatetime, ~N[2025-05-11 07:45:41])
    end

    test "time" do
      value_unchanged(Ash.Type.Time, ~T[07:45:41.000000Z])
    end

    test "time usec" do
      value_unchanged(Ash.Type.TimeUsec, ~T[07:45:41.429903Z])
    end

    test "uuid" do
      value_unchanged(Ash.Type.UUID, Ash.UUID.generate())
    end

    test "uuid v7" do
      value_unchanged(Ash.Type.UUIDv7, Ash.UUIDv7.generate())
    end
  end

  describe "dump ash types" do
    test "atom" do
      value_changed(Ash.Type.Atom, :a, "a")
    end

    test "ci string" do
      value_changed(Ash.Type.CiString, Ash.CiString.new("Hello"), "Hello")
    end

    test "date time" do
      value_changed(Ash.Type.DateTime, ~U[2025-05-11 07:45:41Z], "2025-05-11T07:45:41Z")
    end

    test "duration name" do
      value_changed(Ash.Type.DurationName, :day, "day")
    end

    test "function" do
      value_changed(
        Ash.Type.Function,
        &AshNeo4j.Neo4jHelper.create_node/2,
        "&Elixir.AshNeo4j.Neo4jHelper.create_node/2"
      )
    end

    test "module" do
      value_changed(Ash.Type.Module, AshNeo4j.DataLayer, "Elixir.AshNeo4j.DataLayer")
    end

    test "utc date time" do
      value_changed(Ash.Type.UtcDatetime, ~U[2025-05-11 07:45:41Z], "2025-05-11T07:45:41Z", [precision: :second])
    end

    test "utc date time usec" do
      value_changed(Ash.Type.UtcDatetimeUsec, ~U[2025-05-11 07:45:41.429903Z], "2025-05-11T07:45:41.429903Z", [precision: :microsecond])
    end
  end

  describe "dump ash json types" do
    test "decimal" do
      value_changed(Ash.Type.Decimal, Decimal.new("4.2"), "\"4.2\"")
    end

    test "map with string keys" do
      # map order isn't guaranteed
      _expected = "{\"name\":\"Henry\",\"born\":2018,\"desexed\":true}"
      value_unchanged_roundtrip(Ash.Type.Map, %{"name" => "Henry", "born" => 2018, "desexed" => true})
    end

    test "struct using Ash.Type" do
      # we expect something like "{\"i\":0,\"a\":\"a\",\"f\":1.2,\"b\":false,\"s\":\"Hello\",\"d\":\"4.2\",\"n\":null}" but json order isn't guaranteed
      value_unchanged_roundtrip(Struct, %Struct{})
    end

    test "struct in struct using Ash.Type" do
      # we expect something like "{\"struct\":{\"i\":0,\"a\":\"a\",\"f\":1.2,\"b\":false,\"s\":\"Hello\",\"d\":\"4.2\",\"n\":null}}" but json order isn't guaranteed
      value_unchanged_roundtrip(StructInStruct, %StructInStruct{struct: %Struct{}})
    end
  end

  defp value_unchanged(type, value) do
    assert Dump.dump(type, value) == value
  end

  defp value_changed(type, value, expected, constraints \\ [])

  defp value_changed(type, value, expected, constraints) do
    assert Dump.dump(type, value, constraints) == expected
  end

  defp value_unchanged_roundtrip(type, value, constraints \\ [])

  defp value_unchanged_roundtrip(type, value, constraints) do
    dumped = Dump.dump(type, value, constraints)
    assert Cast.cast(type, dumped) == value
  end
end
