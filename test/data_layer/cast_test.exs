# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.DataLayer.CastTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias AshNeo4j.DataLayer.Cast
  alias AshNeo4j.Test.Resource.Money
  alias AshNeo4j.Test.Type.DogKeyword
  alias AshNeo4j.Test.Type.DogMap
  alias AshNeo4j.Test.Type.DogStruct
  alias AshNeo4j.Test.Type.DogTuple
  alias AshNeo4j.Test.Type.DogTypedStruct
  alias AshNeo4j.Test.Type.DogUnion
  alias AshNeo4j.Test.Util

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
      value_unchanged(Ash.Type.Time, ~T[07:45:41], precision: :second)
    end

    test "time usec" do
      value_unchanged(Ash.Type.TimeUsec, ~T[07:45:41.429903Z])
    end

  end

  describe "cast ash types" do
    test "atom" do
      value_changed(Ash.Type.Atom, "a", :a)
    end

    test "box" do
      sw = Bolty.Types.Point.create(:wgs_84, 151.0, -34.0)
      se = Bolty.Types.Point.create(:wgs_84, 151.5, -34.0)
      ne = Bolty.Types.Point.create(:wgs_84, 151.5, -33.5)
      nw = Bolty.Types.Point.create(:wgs_84, 151.0, -33.5)
      value_changed(AshNeo4j.Type.Box, [sw, se, ne, nw], %AshNeo4j.Type.Box{sw: sw, ne: ne})
    end

    test "geo Point — AshGeo.GeoJson cast_stored is identity on %Geo.Point{}" do
      # The data layer decodes the JSON STRING from <attr>.json into a
      # %Geo.Point{} before handing to Cast (see read_attribute_property/4
      # in data_layer.ex); Cast just sees the struct and dispatches through
      # standard `:ash` cast_ash_type, which is identity for AshGeo.
      pt = %Geo.Point{coordinates: {151.2093, -33.8688}, srid: 4326}
      value_unchanged(AshGeo.GeoJson, pt, geo_types: :point)
    end

    test "ci string" do
      value_changed(Ash.Type.CiString, "Hello", Ash.CiString.new("Hello"))
    end

    test "date time" do
      value_changed(Ash.Type.DateTime, "2025-05-11T07:45:41Z", ~U[2025-05-11 07:45:41Z])
    end

    test "decimal" do
      value_changed(Ash.Type.Decimal, "4.2", Decimal.new("4.2"))
    end

    test "duration name" do
      value_changed(Ash.Type.DurationName, "day", :day)
    end

    test "function - mfa" do
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
      value_changed(Ash.Type.UtcDatetime, "2025-05-11T07:45:41Z", ~U[2025-05-11 07:45:41Z], precision: :second)
    end

    test "utc date time usec" do
      value_changed(Ash.Type.UtcDatetimeUsec, "2025-05-11T07:45:41.429903Z", ~U[2025-05-11 07:45:41.429903Z],
        precision: :microsecond
      )
    end
  end

  describe "cast ash base64 types" do
    test "binary" do
      value_changed(Ash.Type.Binary, "AQID", <<1, 2, 3>>)
    end

    test "url encoded binary" do
      value_changed(Ash.Type.UrlEncodedBinary, "AQID", <<1, 2, 3>>)
    end
  end

  describe "cast ash json types" do
    test "keyword" do
      value_changed(
        DogKeyword,
        "{\"name\":\"Henry\",\"age\":8,\"breed\": \"groodle\"}",
        [name: "Henry", age: 8, breed: :groodle],
        DogKeyword.subtype_constraints()
      )
    end

    test "map" do
      value_changed(
        DogMap,
        "{\"name\":\"Henry\",\"age\":8,\"breed\": \"groodle\"}",
        %{name: "Henry", age: 8, breed: :groodle},
        DogMap.subtype_constraints()
      )
    end

    test "struct" do
      value_changed(
        DogStruct,
        "{\"name\":\"Henry\",\"age\":8,\"breed\": \"groodle\"}",
        %DogStruct{name: "Henry", age: 8, breed: :groodle},
        DogStruct.subtype_constraints()
      )
    end

    test "tuple" do
      value_changed(
        DogTuple,
        "{\"age\":8,\"breed\":\"groodle\",\"name\":\"Henry\"}",
        {"Henry", 8, :groodle},
        DogTuple.subtype_constraints()
      )
    end

    test "typed struct" do
      value_changed(
        DogTypedStruct,
        "{\"name\":\"Henry\",\"age\":8,\"breed\": \"groodle\"}",
        %DogTypedStruct{name: "Henry", age: 8, breed: :groodle},
        DogTypedStruct.subtype_constraints()
      )
    end

    test "embedded resource" do
      value_changed(Money, "{\"currency\":\"aud\",\"amount\":100}", %Money{amount: 100, currency: :aud})
    end

    test "tagged union" do
      value_changed(
        DogUnion,
        "{\"type\":\"typed_struct\",\"value\":{\"age\":8,\"breed\":\"groodle\",\"name\":\"Henry\"}}",
        %Ash.Union{type: :typed_struct, value: %DogTypedStruct{name: "Henry", age: 8, breed: :groodle}},
        Util.init_constraints(DogUnion)
      )
    end
  end

  describe "cast uuid types" do
    test "uuid" do
      value_unchanged(Ash.Type.UUID, Ash.UUID.generate())
    end

    test "uuid v7" do
      value_unchanged(Ash.Type.UUIDv7, Ash.UUIDv7.generate())
    end
  end

  describe "cast arrays" do
    test "array of atoms" do
      value_changed({:array, Ash.Type.Atom}, ["a", "b"], [:a, :b])
    end

    test "array of booleans" do
      value_unchanged({:array, Ash.Type.Boolean}, [true, false])
    end

    test "array of maps" do
      value_changed({:array, Ash.Type.Map}, ["{\"a\":\"a\"}", "{\"b\":\"b\"}"], [%{"a" => "a"}, %{"b" => "b"}])
    end

    test "array of embedded resources" do
      value_changed(
        {:array, Money},
        ["{\"currency\":\"aud\",\"amount\":100}", "{\"currency\":\"sek\",\"amount\":650}"],
        [
          %Money{amount: 100, currency: :aud},
          %Money{amount: 650, currency: :sek}
        ]
      )
    end

    test "array of base64 encoded binaries" do
      value_changed({:array, Ash.Type.Binary}, ["AQID", "BAUG"], [<<1, 2, 3>>, <<4, 5, 6>>])
    end

    test "array of typed structs" do
      value_changed(
        {:array, DogTypedStruct},
        [
          "{\"name\":\"Henry\",\"age\":8,\"breed\": \"groodle\"}",
          "{\"name\":\"Kipper\",\"age\":15,\"breed\": \"labradoodle\"}"
        ],
        [
          %DogTypedStruct{name: "Henry", age: 8, breed: :groodle},
          %DogTypedStruct{name: "Kipper", age: 15, breed: :labradoodle}
        ]
      )
    end
  end

  describe "errors" do
    test "not an Ash.Type" do
      assert {:error, _reason} = Cast.cast(Ash.Resource, "fred")
    end

    test "not valid json" do
      assert {:error, _reason} = Cast.cast(Ash.Type.Map, "{name:\"Henry\"")
    end

    test "cast - module not loaded returns error" do
      assert {:error, reason} =
               AshNeo4j.DataLayer.Cast.cast(
                 Ash.Type.Module,
                 "Elixir.NonExistent.Module.ThatNeverExisted",
                 []
               )

      assert reason =~ "cannot cast"
    end

    test "cast - function module not loaded returns error" do
      assert {:error, reason} =
               AshNeo4j.DataLayer.Cast.cast(
                 Ash.Type.Function,
                 "&NonExistent.Module.ThatNeverExisted.fun/1",
                 []
               )

      assert reason =~ "cannot cast"
    end

    test "cast - module isn't a known Ash.Type" do
      assert {:error, _} =
               Cast.cast(
                 AshNeo4j.DataLayer,
                 ~s({"type":"AshNeo4j.DataLayer","value":{"handle":"Henry"}}),
                 []
               )
    end
  end

  defp value_unchanged(type, value, constraints \\ []) do
    assert Cast.cast(type, value, constraints) == {:ok, value}
  end

  defp value_changed(type, value, expected, constraints \\ []) do
    assert Cast.cast(type, value, constraints) == {:ok, expected}
  end
end
