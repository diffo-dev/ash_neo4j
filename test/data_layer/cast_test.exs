# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.DataLayer.Cast.Test do
  @moduledoc false
  use ExUnit.Case, async: false
  alias AshNeo4j.DataLayer.Cast
  alias AshNeo4j.Test.Struct
  alias AshNeo4j.Test.StructInStruct

  describe "cast native types" do
    test "using Ash.Type alias" do
      value_changed(:atom, "a", :a)
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

  describe "cast ash types" do
    test "atom" do
      value_changed(Ash.Type.Atom, "a", :a)
    end

    test "ci string" do
      value_changed(Ash.Type.CiString, "Hello", Ash.CiString.new("Hello"))
    end

    test "date time" do
      value_changed(Ash.Type.DateTime, "2025-05-11T07:45:41Z", ~U[2025-05-11 07:45:41Z])
    end

    test "duration name" do
      value_changed(Ash.Type.DurationName, "day", :day)
    end

    test "function" do
      value_changed(
        Ash.Type.Function,
        "&Elixir.AshNeo4j.Neo4jHelper.create_node/2",
        &AshNeo4j.Neo4jHelper.create_node/2
      )
    end

    test "module" do
      value_changed(Ash.Type.Module, "Elixir.AshNeo4j.DataLayer", AshNeo4j.DataLayer)
    end

    test "utc date time" do
      value_changed(Ash.Type.UtcDatetime, "2025-05-11T07:45:41Z", ~U[2025-05-11 07:45:41Z], [precision: :second])
    end

    test "utc date time usec" do
      value_changed(Ash.Type.UtcDatetimeUsec, "2025-05-11T07:45:41.429903Z", ~U[2025-05-11 07:45:41.429903Z], [precision: :microsecond])
    end
  end

  describe "cast ash json types" do
    test "decimal" do
      value_changed(Ash.Type.Decimal, "\"4.2\"", Decimal.new("4.2"))
    end

    test "map with string keys" do
      value_changed(Ash.Type.Map, "{\"name\":\"Henry\",\"born\":2018,\"desexed\": true}", %{
        "name" => "Henry",
        "born" => 2018,
        "desexed" => true
      })
    end

    test "struct using Ash.Type" do
      value_changed(Struct, "{\"s\":\"Hello\"}", %Struct{s: "Hello"})
    end

    test "struct in struct using Ash.Type" do
      value_changed(StructInStruct, "{\"struct\": {\"s\":\"Hello\"}}", %StructInStruct{struct: %Struct{s: "Hello"}})
    end

  end

  defp value_unchanged(type, value) do
    assert Cast.cast(type, value) == value
  end

  defp value_changed(type, value, expected, constraints \\ [])

  defp value_changed(type, value, expected, constraints) do
    casted = Cast.cast(type, value, constraints)
    assert casted == expected
  end
end
