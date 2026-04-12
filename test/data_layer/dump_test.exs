# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.DataLayer.Dump.Test do
  @moduledoc false
  use ExUnit.Case, async: false
  alias AshNeo4j.DataLayer.Dump
  alias AshNeo4j.Test.Resource.Money
  alias AshNeo4j.Test.Type.DogKeyword
  alias AshNeo4j.Test.Type.DogMap
  alias AshNeo4j.Test.Type.DogStruct
  alias AshNeo4j.Test.Type.DogTuple
  alias AshNeo4j.Test.Type.DogTypedStruct

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
      value_unchanged(Ash.Type.Time, ~T[07:45:41], precison: :second)
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

    test "decimal" do
      value_changed(Ash.Type.Decimal, Decimal.new("4.2"), "4.2")
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
      value_changed(Ash.Type.UtcDatetime, ~U[2025-05-11 07:45:41Z], "2025-05-11T07:45:41Z", precision: :second)
    end

    test "utc date time usec" do
      value_changed(Ash.Type.UtcDatetimeUsec, ~U[2025-05-11 07:45:41.429903Z], "2025-05-11T07:45:41.429903Z",
        precision: :microsecond
      )
    end
  end

  describe "dump ash base64 types" do
    @tag :base64
    test "binary" do
      value_changed(Ash.Type.Binary, <<1, 2, 3>>, "AQID")
    end

    @tag :base64
    test "url encoded binary" do
      value_changed(Ash.Type.UrlEncodedBinary, <<1, 2, 3>>, "AQID")
    end
  end

  describe "dump ash json types" do
    @tag :keyword
    test "keyword" do
      value_changed(
        DogKeyword,
        [name: "Henry", age: 8, breed: :groodle],
        "{\"age\":8,\"breed\":\"groodle\",\"name\":\"Henry\"}",
        DogKeyword.subtype_constraints()
      )
    end

    test "map" do
      value_changed(
        DogMap,
        %{name: "Henry", age: 8, breed: :groodle},
        "{\"age\":8,\"breed\":\"groodle\",\"name\":\"Henry\"}",
        DogMap.subtype_constraints()
      )
    end

    test "struct" do
      value_changed(
        DogStruct,
        %{name: "Henry", age: 8, breed: :groodle},
        "{\"age\":8,\"breed\":\"groodle\",\"name\":\"Henry\"}",
        DogStruct.subtype_constraints()
      )
    end

    @tag :tuple
    test "tuple" do
      value_changed(
        DogTuple,
        {"Henry", 8, :groodle},
        "{\"age\":8,\"breed\":\"groodle\",\"name\":\"Henry\"}",
        DogTuple.subtype_constraints()
      )
    end

    test "typed struct" do
      value_changed(
        DogTypedStruct,
        %{name: "Henry", age: 8, breed: :groodle},
        "{\"age\":8,\"breed\":\"groodle\",\"name\":\"Henry\"}",
        DogTypedStruct.subtype_constraints()
      )
    end

    test "embedded resource" do
      value_changed(Money, %Money{amount: 100, currency: :aud}, "{\"amount\":100,\"currency\":\"aud\"}")
    end
  end

  describe "dump arrays" do
    test "array of atoms" do
      value_changed({:array, Ash.Type.Atom}, [:a, :b], ["a", "b"])
    end

    test "array of booleans" do
      value_unchanged({:array, Ash.Type.Boolean}, [true, false])
    end

    test "array of maps" do
      value_changed({:array, Ash.Type.Map}, [%{"a" => "a"}, %{"b" => "b"}], ["{\"a\":\"a\"}", "{\"b\":\"b\"}"])
    end

    @tag :base64
    test "array of base64 encoded binaries" do
      value_changed({:array, Ash.Type.Binary}, [<<1, 2, 3>>, <<4, 5, 6>>], ["AQID", "BAUG"])
    end

    test "array of embedded resources" do
      value_changed(
        {:array, Money},
        [%Money{amount: 100, currency: :aud}, %Money{amount: 650, currency: :sek}],
        ["{\"amount\":100,\"currency\":\"aud\"}", "{\"amount\":650,\"currency\":\"sek\"}"]
      )
    end
  end

  describe "errors" do
    test "not an Ash.Type" do
      raises(Ash.Resource, "fred")
    end

    test "invalid atom" do
      raises(Ash.Type.Atom, "invalid atom")
    end
  end

  defp raises(type, value, constraints \\ []) do
    assert_raise RuntimeError, fn -> Dump.dump(type, value, constraints) end
  end

  defp value_unchanged(type, value, constraints \\ []) do
    assert Dump.dump(type, value, constraints) == value
  end

  defp value_changed(type, value, expected, constraints \\ []) do
    assert Dump.dump(type, value, constraints) == expected
  end
end
