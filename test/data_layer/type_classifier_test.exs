# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.DataLayer.TypeClassifierTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias AshNeo4j.DataLayer.TypeClassifier

  @native_types [
    Ash.Type.Boolean,
    Ash.Type.Date,
    Ash.Type.Duration,
    Ash.Type.Float,
    Ash.Type.Integer,
    Ash.Type.NaiveDatetime,
    Ash.Type.String,
    Ash.Type.Time,
    Ash.Type.TimeUsec
  ]

  @ash_base64_types [
    Ash.Type.Binary,
    Ash.Type.UrlEncodedBinary
  ]

  @ash_json_types [
    Ash.Type.Keyword,
    Ash.Type.Map,
    Ash.Type.Struct,
    Ash.Type.Tuple,
    Ash.Type.Union,
    AshNeo4j.Test.Resource.Money,
    AshNeo4j.Test.Type.DogMap,
    AshNeo4j.Test.Type.DogStruct,
    AshNeo4j.Test.Type.DogTypedStruct
  ]

  @ash_uuid_types [
    Ash.Type.UUID,
    Ash.Type.UUIDv7
  ]

  @ash_types [
    Ash.Type.Atom,
    Ash.Type.CiString,
    Ash.Type.DateTime,
    Ash.Type.Decimal,
    Ash.Type.DurationName,
    Ash.Type.Function,
    Ash.Type.Module,
    Ash.Type.UtcDatetime,
    Ash.Type.UtcDatetimeUsec
  ]

  @unsupported_types [
    Ash.Type.File,
    Ash.Type.Term,
    Ash.Type.Vector
  ]

  @unrecognized_types [
    nil,
    :ATOM,
    Ash.Type,
    Ash.Type.NewType,
    Ash.Type.Enum,
    Ash.TypedStruct,
    Ash.Resource
  ]

  describe "Datalayer Type Classifier tests" do
    test "atom using alias" do
      assert TypeClassifier.classify(:atom) == {:ok, :ash, Ash.Type.Atom}
    end

    test "native types" do
      Enum.each(@native_types, fn type ->
        assert TypeClassifier.classify(type) == {:ok, :native, type}
      end)
    end

    test "ash types" do
      Enum.each(@ash_types, fn type ->
        assert TypeClassifier.classify(type) == {:ok, :ash, type}
      end)
    end

    test "ash base64 types" do
      Enum.each(@ash_base64_types, fn type ->
        assert TypeClassifier.classify(type) == {:ok, :ash_base64, type}
      end)
    end

    test "ash uuid types" do
      Enum.each(@ash_uuid_types, fn type ->
        assert TypeClassifier.classify(type) == {:ok, :ash_uuid, type}
      end)
    end

    test "ash json types" do
      Enum.each(@ash_json_types, fn type ->
        assert TypeClassifier.classify(type) == {:ok, :ash_json, type}
      end)
    end

    test "unsupported types" do
      Enum.each(@unsupported_types, fn type ->
        assert TypeClassifier.classify(type) == {:error, :unsupported, type}
      end)
    end

    test "array atom using alias" do
      assert TypeClassifier.classify({:array, :atom}) == {:ok, :array, {:ok, :ash, Ash.Type.Atom}}
    end

    test "array of native types" do
      Enum.each(@native_types, fn type ->
        assert TypeClassifier.classify({:array, type}) == {:ok, :array, {:ok, :native, type}}
      end)
    end

    test "array of ash types" do
      Enum.each(@ash_types, fn type ->
        assert TypeClassifier.classify({:array, type}) == {:ok, :array, {:ok, :ash, type}}
      end)
    end

    test "array of ash base64 types" do
      Enum.each(@ash_base64_types, fn type ->
        assert TypeClassifier.classify({:array, type}) == {:ok, :array, {:ok, :ash_base64, type}}
      end)
    end

    test "array of ash json types" do
      Enum.each(@ash_json_types, fn type ->
        assert TypeClassifier.classify({:array, type}) == {:ok, :array, {:ok, :ash_json, type}}
      end)
    end

    test "array of ash uuid types" do
      Enum.each(@ash_uuid_types, fn type ->
        assert TypeClassifier.classify({:array, type}) == {:ok, :array, {:ok, :ash_uuid, type}}
      end)
    end

    test "array of unsupported types" do
      Enum.each(@unsupported_types, fn type ->
        assert TypeClassifier.classify({:array, type}) == {:ok, :array, {:error, :unsupported, type}}
      end)
    end

    test "unrecognized types" do
      Enum.each(@unrecognized_types, fn type ->
        assert TypeClassifier.classify(type) == {:error, :unrecognized, type}
      end)
    end
  end
end
