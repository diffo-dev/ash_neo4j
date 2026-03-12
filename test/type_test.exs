# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Type do
  @moduledoc false
  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Neo4jHelper
  alias AshNeo4j.Test.Resource.Type
  alias AshNeo4j.Test.Resource.Money
  alias AshNeo4j.Test.Struct
  alias AshNeo4j.Test.StructInStruct
  alias AshNeo4j.Test.Util

  use ExUnit.Case, async: false

  setup_all do
    BoltyHelper.start()
  end

  setup do
    on_exit(fn ->
      Neo4jHelper.delete_nodes(:Type)
    end)
  end

  @type_attributes %{
    array_atom: [:a, :b, :c],
    array_integer: [1, 2, 3],
    array_string: ["a", "b", "c"],
    array_boolean: [true, true, false],
    array_map: [%{a: "a"}, %{b: "b"}],
    array_struct: [%Struct{}],
    # note neo4j arrays must all be same neo4j type (in this case all strings)
    array_term: [:a, "a", %Struct{}],
    atom: :a,
    binary: <<1, 2, 3>>,
    boolean: true,
    ci_string: "HELLO",
    date: ~D[2025-05-11],
    datetime: ~U[2025-05-11 07:45:41Z],
    decimal: Decimal.new("4.2"),
    duration: %Duration{year: 1, month: 2, week: 3, day: 4, hour: 5, minute: 6, second: 7, microsecond: {8, 6}},
    float: 1.23456789,
    function: &Neo4jHelper.create_node/2,
    integer: 1,
    json_string: "{\"a\": \"a\", \"b\": 1, \"c\": false}",
    keyword: [a: :atom, s: "string"],
    map: %{a: "a", b: 1, c: false, d: nil},
    mapset: MapSet.new([1, :two, false]),
    module: AshNeo4j.DataLayer,
    naive_datetime: ~N[2025-05-11 07:45:41],
    # regex: ~r/foo/iu,
    string: "Hello",
    struct: %Struct{s: "Wow"},
    struct_in_struct: %StructInStruct{struct: %Struct{s: "Wow"}},
    term: %{"aEnd" => 1, "zEnd" => 13},
    time: ~T[07:45:41Z],
    time_usec: ~T[07:45:41.429903Z],
    tuple: {:a, 1, false},
    utc_datetime_usec: ~U[2025-05-11 07:45:41.429903Z],
    url: "aHR0cHM6Ly93d3cuZGlmZm8uZGV2Lw"
  }

  @type_node_properties %{
    "arrayAtom" => [":a", ":b", ":c"],
    "arrayInteger" => [1, 2, 3],
    "arrayString" => ["a", "b", "c"],
    "arrayBoolean" => [true, true, false],
    "arrayMap" => ["%{a: \"a\"}", "%{b: \"b\"}"],
    "arrayStruct" => [
      "%AshNeo4j.Test.Struct{a: :a, b: false, d: Decimal.new(\"4.2\"), f: 1.2, i: 0, n: nil, s: \"Hello\"}"
    ],
    # note neo4j arrays must all be same neo4j type (in this case all strings)
    "arrayTerm" => [
      ":a",
      "a",
      "%AshNeo4j.Test.Struct{a: :a, b: false, d: Decimal.new(\"4.2\"), f: 1.2, i: 0, n: nil, s: \"Hello\"}"
    ],
    "atom" => ":a",
    "binary" => "\x01\x02\x03",
    "boolean" => true,
    "ciString" => "HELLO",
    "date" => "2025-05-11",
    "datetime" => "2025-05-11T07:45:41Z",
    "decimal" => "Decimal.new(\"4.2\")",
    "duration" => "P1Y2M3W4DT5H6M7.000008S",
    "float" => 1.23456789,
    "function" => "&AshNeo4j.Neo4jHelper.create_node/2",
    "integer" => 1,
    "jsonString" => "{\"a\": \"a\", \"b\": 1, \"c\": false}",
    "keyword" => ["{:a, :atom}", "{:s, string}"],
    # serialisation order indeterminate
    "map" => "%{a: \"a\", b: 1, c: false, d: nil}",
    # serialisation order indeterminate
    "mapset" => "MapSet.new([1, :two, false])",
    "module" => ":Elixir.AshNeo4j.DataLayer",
    "naiveDatetime" => "2025-05-11T07:45:41",
    # "regex" => "~r/foo/iu",
    "string" => "Hello",
    "struct" => "%AshNeo4j.Test.Struct{a: :a, b: false, d: Decimal.new(\"4.2\"), f: 1.2, i: 0, n: nil, s: \"Wow\"}",
    "structInStruct" =>
      "%AshNeo4j.Test.StructInStruct{struct: %AshNeo4j.Test.Struct{a: :a, b: false, d: Decimal.new(\"4.2\"), f: 1.2, i: 0, n: nil, s: \"Wow\"}}",
    "term" => "%{\"aEnd\" => 1, \"zEnd\" => 13}",
    "time" => "07:45:41",
    "timeUsec" => "07:45:41.429903",
    "tuple" => "{:a, 1, false}",
    "utcDatetimeUsec" => "2025-05-11T07:45:41.429903Z",
    "url" => "aHR0cHM6Ly93d3cuZGlmZm8uZGV2Lw"
  }

  @url "https://www.diffo.dev/"

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
      Enum.each(@type_node_properties, fn {key, _value} -> assert Map.get(node.properties, "#{key}") == nil end)
    end

    test "type node with properties can be created using Neo4jHelper" do
      assert {:ok, %{records: records}} = Neo4jHelper.create_node([:Type], @type_node_properties)
      assert length(records) == 1
      node = records |> List.first() |> List.first()
      assert node.labels == ["Type"]
      # map and mapset have indeterminate order so we don't check them exactly
      refute Map.get(node.properties, "map") == nil
      refute Map.get(node.properties, "mapset") == nil

      Enum.each(Map.drop(@type_node_properties, ["map", "mapset"]), fn {key, value} ->
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
      Enum.each(@type_attributes, fn {key, value} -> assert Map.get(type, key) == value end)
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
      {:ok, type} = Type |> Ash.Changeset.for_create(:create, @type_attributes) |> Ash.create()
      assert type.url == @url

      Enum.each(Map.drop(@type_attributes, [:url, :duration]), fn {key, value} -> assert Map.get(type, key) == value end)

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
      assert "Domain" in type.__metadata__.labels
      assert is_integer(type.__metadata__.node_id)
    end
  end

  describe "Ash Destroy Type tests" do
    test "type can be destroyed using ash" do
      {:ok, type} = Type |> Ash.Changeset.for_create(:create, %{}) |> Ash.create()
      :ok = type |> Ash.destroy!()
    end
  end
end
