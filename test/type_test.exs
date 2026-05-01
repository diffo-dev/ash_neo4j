# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.TypeTest do
  @moduledoc false
  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Neo4jHelper
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Type
  alias AshNeo4j.Test.Resource.Money
  alias AshNeo4j.Test.Type.DogStruct
  alias AshNeo4j.Test.Type.DogTypedStruct
  alias AshNeo4j.Test.Util

  use ExUnit.Case, async: true

  import Ash.CiString

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  @type_attributes %{
    array_atom: [:a, :b, :c],
    array_binary: [<<1, 2, 3>>, <<4, 5, 6>>],
    array_integer: [1, 2, 3],
    array_string: ["a", "b", "c"],
    array_boolean: [true, true, false],
    array_map: [
      %{name: "Henry", age: 8, breed: :groodle},
      %{name: "Kipper", age: 15, breed: :labradoodle}
    ],
    array_struct: [
      %DogStruct{name: "Henry", age: 8, breed: :groodle},
      %DogStruct{name: "Kipper", age: 15, breed: :labradoodle}
    ],
    array_typed_struct: [
      %DogTypedStruct{name: "Henry", age: 8, breed: :groodle},
      %DogTypedStruct{name: "Kipper", age: 15, breed: :labradoodle}
    ],
    atom: :a,
    binary: <<1, 2, 3>>,
    boolean: true,
    ci_string: ~i(Hello),
    date: ~D[2025-05-11],
    datetime: ~U[2025-05-11 07:45:41Z],
    decimal: Decimal.new("4.2"),
    duration: %Duration{day: 25, hour: 5, minute: 6, second: 7, microsecond: {8, 6}},
    float: 1.23456789,
    function: &Neo4jHelper.create_node/2,
    integer: 1,
    keyword: [name: "Henry", age: 8, breed: :groodle],
    map: %{name: "Henry", age: 8, breed: :groodle},
    module: AshNeo4j.DataLayer,
    naive_datetime: ~N[2025-05-11 07:45:41.000000],
    string: "Hello",
    struct: %DogStruct{name: "Henry", age: 8, breed: :groodle},
    time: ~T[07:45:41.000000],
    time_usec: ~T[07:45:41.429903],
    tuple: {"Henry", 8, :groodle},
    typed_struct: %DogTypedStruct{name: "Henry", age: 8, breed: :groodle},
    union: %Ash.Union{type: :typed_struct, value: %DogTypedStruct{name: "Henry", age: 8, breed: :groodle}},
    utc_datetime_usec: ~U[2025-05-11 07:45:41.429903Z],
    url_encoded_binary: <<1, 2, 3>>,
    uuid4: Ash.UUID.generate(),
    uuid7: Ash.UUIDv7.generate()
  }

  @type_node_properties %{
    "arrayAtom" => ["a", "b", "c"],
    "arrayInteger" => [1, 2, 3],
    "arrayString" => ["a", "b", "c"],
    "arrayBoolean" => [true, true, false],
    "arrayMap" => [
      "{\"age\":8,\"breed\":\"groodle\",\"name\":\"Henry\"}",
      "{\"age\":15,\"breed\":\"labradoodle\",\"name\":\"Kipper\"}"
    ],
    "arrayBinary" => ["AQID", "BAUG"],
    "arrayStruct" => [
      "{\"age\":8,\"breed\":\"groodle\",\"name\":\"Henry\"}",
      "{\"age\":15,\"breed\":\"labradoodle\",\"name\":\"Kipper\"}"
    ],
    "arrayTypedStruct" => [
      "{\"age\":8,\"breed\":\"groodle\",\"name\":\"Henry\"}",
      "{\"age\":15,\"breed\":\"labradoodle\",\"name\":\"Kipper\"}"
    ],
    "atom" => "a",
    "binary" => "AQID",
    "boolean" => true,
    "ciString" => "Hello",
    "date" => ~D[2025-05-11],
    "datetime" => "2025-05-11T07:45:41Z",
    "decimal" => "4.2",
    "duration" => %Duration{day: 25, hour: 5, minute: 6, second: 7, microsecond: {8, 6}},
    "float" => 1.23456789,
    "function" => "&AshNeo4j.Neo4jHelper.create_node/2",
    "integer" => 1,
    "keyword" => "{\"age\":8,\"breed\":\"groodle\",\"name\":\"Henry\"}",
    "map" => "{\"age\":8,\"breed\":\"groodle\",\"name\":\"Henry\"}",
    "module" => "Elixir.AshNeo4j.DataLayer",
    "naiveDatetime" => ~N[2025-05-11 07:45:41.000000],
    "string" => "Hello",
    "struct" => "{\"age\":8,\"breed\":\"groodle\",\"name\":\"Henry\"}",
    "time" => ~T[07:45:41],
    "timeUsec" => ~T[07:45:41.429903],
    "tuple" => "{\"age\":8,\"breed\":\"groodle\",\"name\":\"Henry\"}",
    "typedStruct" => "{\"age\":8,\"breed\":\"groodle\",\"name\":\"Henry\"}",
    "union" => "{\"type\":\"typed_struct\",\"value\":{\"age\":8,\"breed\":\"groodle\",\"name\":\"Henry\"}}",
    "utcDatetimeUsec" => "2025-05-11T07:45:41.429903Z",
    "urlEncodedBinary" => "AQID",
    "uuid4" => @type_attributes.uuid4,
    "uuid7" => @type_attributes.uuid7
  }

  describe "Neo4jHelper Type tests" do
    test "type node without properties can be created using Neo4jHelper" do
      assert {:ok, %{records: records}} = Neo4jHelper.create_node([:Type], %{})
      assert length(records) == 1
      node = records |> List.first() |> List.first()
      assert node.labels == ["Type"]
    end

    test "type node without properties can be read using Neo4jHelper" do
      Neo4jHelper.create_node([:Type], %{})
      assert {:ok, %{records: records}} = Neo4jHelper.read_nodes(:Type, %{})
      assert length(records) == 1
      node = records |> List.first() |> List.first()
      assert node.labels == ["Type"]
      assert Enum.empty?(node.properties)
    end

    test "type node with native properties can be created using Neo4jHelper" do
      properties = Map.take(@type_node_properties, ["atom", "boolean", "float", "integer", "string"])
      assert {:ok, %{records: records}} = Neo4jHelper.create_node([:Type], properties)
      assert length(records) == 1
      node = records |> List.first() |> List.first()
      assert node.labels == ["Type"]

      Enum.each(properties, fn {key, value} ->
        assert Map.get(node.properties, "#{key}") == value
      end)
    end

    test "type node with array properties can be created using Neo4jHelper" do
      properties =
        Map.take(@type_node_properties, [
          "arrayAtom",
          "arrayInteger",
          "arrayString",
          "arrayBoolean",
          "arrayMap",
          "arrayStruct"
        ])

      assert {:ok, %{records: records}} = Neo4jHelper.create_node([:Type], properties)
      assert length(records) == 1
      node = records |> List.first() |> List.first()
      assert node.labels == ["Type"]

      Enum.each(properties, fn {key, value} ->
        assert Map.get(node.properties, "#{key}") == value
      end)
    end

    test "type node with temporal properties can be created using Neo4jHelper" do
      properties =
        Map.take(@type_node_properties, [
          "date",
          "datetime",
          "duration",
          "naiveDatetime",
          "time",
          "timeUsec",
          "utcDatetimeUsec"
        ])

      assert {:ok, %{records: records}} = Neo4jHelper.create_node([:Type], properties)
      assert length(records) == 1
      node = records |> List.first() |> List.first()
      assert node.labels == ["Type"]

      # check properties that can be directly compared
      Enum.each(Map.drop(properties, ["duration", "time"]), fn {key, value} ->
        assert Map.get(node.properties, "#{key}") == value
      end)
    end

    test "type node with complex properties can be created using Neo4jHelper" do
      properties = Map.take(@type_node_properties, ["map", "struct", "tuple", "keyword"])
      assert {:ok, %{records: records}} = Neo4jHelper.create_node([:Type], properties)
      assert length(records) == 1
      node = records |> List.first() |> List.first()
      assert node.labels == ["Type"]

      Enum.each(properties, fn {key, value} ->
        assert Map.get(node.properties, "#{key}") == value
      end)
    end

    test "type node with properties can be read using Neo4jHelper" do
      Neo4jHelper.create_node([:Type], @type_node_properties)
      assert {:ok, %{records: records}} = Neo4jHelper.read_nodes(:Type, %{string: "Hello"})
      assert length(records) == 1
      node = records |> List.first() |> List.first()
      assert node.labels == ["Type"]
    end
  end

  describe "Ash Read Type tests" do
    test "type node can be read using ash" do
      properties = Map.put(@type_node_properties, :uuid, Ash.UUID.generate())
      Neo4jHelper.create_node([:Type], properties)
      type = Ash.read_one!(Type)
      assert type.uuid == properties.uuid

      Enum.each(@type_attributes, fn {key, value} ->
        assert Map.get(type, key) == value
      end)
    end

    test "type node has metadata on read" do
      properties = Map.put(@type_node_properties, :uuid, Ash.UUID.generate())
      Neo4jHelper.create_node([:Domain, :Type], properties)
      type = Ash.read_one!(Type)
      assert is_struct(type.__meta__, Ecto.Schema.Metadata)
      assert type.__meta__.state == :loaded
      assert type.__metadata__
      assert type.__metadata__.data_layer == AshNeo4j.DataLayer
      assert "Type" in type.__metadata__.labels
      assert "Domain" in type.__metadata__.labels
      assert is_integer(type.__metadata__.node_id)
    end
  end

  describe "Ash Create Type tests" do
    test "type node can be created using ash without properties" do
      {:ok, type} = Type |> Ash.Changeset.for_create(:create, %{}) |> Ash.create()
      refute type.uuid == nil
      assert type.atom == :a
      Enum.each(Map.drop(@type_attributes, [:uuid, :atom]), fn {key, _value} -> assert Map.get(type, key) == nil end)
    end

    test "type node can be created using ash with properties" do
      {:ok, type} =
        Type |> Ash.Changeset.for_create(:create, @type_attributes) |> Ash.create()

      # check properties that can be directly compared
      Enum.each(
        Map.drop(@type_attributes, [:duration, :time, :map, :array_map]),
        fn {key, value} ->
          actual = Map.get(type, key)
          assert actual == value
        end
      )

      # note the duration returned is equivalent, but differs in days and weeks (neo4j doesn't represent weeks and days separately)
      assert Util.durations_equal(type.duration, @type_attributes.duration)
    end

    test "type node can be created using ash with embedded resource property" do
      {:ok, money} = Money |> Ash.Changeset.for_create(:create, %{amount: 1000, currency: :sek}) |> Ash.create()
      {:ok, type} = Type |> Ash.Changeset.for_create(:create, %{money: money}) |> Ash.create()
      assert type.money.amount == 1000
      assert type.money.currency == :sek
    end

    test "type node can be created using ash with array embedded resource property" do
      {:ok, money1} = Money |> Ash.Changeset.for_create(:create, %{amount: 1000, currency: :sek}) |> Ash.create()
      {:ok, money2} = Money |> Ash.Changeset.for_create(:create, %{amount: 200, currency: :aud}) |> Ash.create()
      {:ok, type} = Type |> Ash.Changeset.for_create(:create, %{array_money: [money1, money2]}) |> Ash.create()
      assert length(type.array_money) == 2
      assert hd(type.array_money).currency == :sek
      assert hd(tl(type.array_money)).currency == :aud
    end

    test "type node has metadata on create" do
      {:ok, type} = Type |> Ash.Changeset.for_create(:create, %{}) |> Ash.create()
      assert is_struct(type.__meta__, Ecto.Schema.Metadata)
      assert type.__meta__.state == :loaded
      assert type.__metadata__
      assert type.__metadata__.data_layer == AshNeo4j.DataLayer
      assert "Type" in type.__metadata__.labels
      assert "SRM" in type.__metadata__.labels
      assert is_integer(type.__metadata__.node_id)
    end

    test "type node is created with ash and nils are suppressed in json blobs" do
      {:ok, type} =
        Type
        |> Ash.Changeset.for_create(:create, %{string: "Hello", typed_struct: %DogTypedStruct{name: "Henry", age: 8}})
        |> Ash.create()

      {:ok, read_type} = Ash.get(Type, type.uuid)
      assert read_type.typed_struct == %DogTypedStruct{name: "Henry", age: 8}

      # check typed struct encoding, nil should be suppressed, type should be erased, fields should be sorted alphabetically
      assert {:ok, %{records: records}} = Neo4jHelper.read_nodes(:Type, %{string: "Hello"})
      assert length(records) == 1
      node = records |> List.first() |> List.first()

      %{"typedStruct" => typed_struct} = node.properties

      assert typed_struct == ~s({"age":8,"name":"Henry"})
    end

    test "type node can be created then read with ash" do
      {:ok, type} = Type |> Ash.Changeset.for_create(:create, @type_attributes) |> Ash.create()
      read_type = Ash.read_one!(Type)
      assert read_type.uuid == type.uuid
    end
  end

  describe "defensive tests" do
    test "cast function - module not loaded returns error" do
      Neo4jHelper.create_node([:Type], %{
        "uuid" => Ash.UUID.generate(),
        "function" => "&NonExistent.Module.my_fun/2"
      })

      assert {:error, _} = Ash.read_one(Type)
    end

    test "cast module - module not loaded returns error" do
      Neo4jHelper.create_node([:Type], %{
        "uuid" => Ash.UUID.generate(),
        "module" => "Elixir.NonExistent.Module"
      })

      assert {:error, _} = Ash.read_one(Type)
    end
  end

  describe "Ash Destroy Type tests" do
    test "type can be destroyed using ash" do
      {:ok, type} = Type |> Ash.Changeset.for_create(:create, %{}) |> Ash.create()
      :ok = type |> Ash.destroy!()
    end
  end
end
