# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.MermaidTest do
  @moduledoc """
  Pure renderer tests for `AshNeo4j.Mermaid.flowchart/2` — builds Bolty graph
  structs directly, no Neo4j connection required.
  """
  use ExUnit.Case, async: true

  alias AshNeo4j.Mermaid
  alias Bolty.Response
  alias Bolty.Types.{Node, Path, Relationship}

  doctest AshNeo4j.Mermaid

  defp response(rows), do: %Response{results: rows}

  defp node(id, labels, properties),
    do: %Node{id: id, labels: labels, properties: properties, element_id: "4:e:#{id}"}

  describe "nodes" do
    test "renders labels and properties, sorted by key" do
      n = node(0, ["Person"], %{"name" => "Bill", "born" => 1949})

      assert Mermaid.flowchart(response([%{"n" => n}])) ==
               """
               flowchart TD
                   n0["Person<br/>born: 1949<br/>name: Bill"]\
               """
    end

    test "joins multiple labels with a colon" do
      n = node(0, ["Cinema", "Actor"], %{})
      assert Mermaid.flowchart(response([%{"n" => n}])) =~ ~s(n0["Cinema:Actor"])
    end

    test "de-duplicates a node returned across rows" do
      n = node(7, ["Person"], %{"name" => "Bill"})
      rendered = Mermaid.flowchart(response([%{"n" => n}, %{"n" => n}]))

      assert rendered ==
               """
               flowchart TD
                   n7["Person<br/>name: Bill"]\
               """
    end

    test "ignores scalar values in rows" do
      n = node(0, ["Person"], %{})
      rendered = Mermaid.flowchart(response([%{"n" => n, "count" => 5, "name" => "Bill"}]))
      assert rendered == "flowchart TD\n    n0[\"Person\"]"
    end

    test "formats nil, boolean and number property values" do
      n = node(0, ["X"], %{"a" => nil, "b" => true, "c" => 3.5})

      assert Mermaid.flowchart(response([%{"n" => n}])) ==
               "flowchart TD\n    n0[\"X<br/>a: null<br/>b: true<br/>c: 3.5\"]"
    end
  end

  describe "options" do
    test ":direction overrides the default TD" do
      n = node(0, ["Person"], %{})
      assert Mermaid.flowchart(response([%{"n" => n}]), direction: "LR") =~ "flowchart LR"
      assert Mermaid.flowchart(response([%{"n" => n}]), direction: :BT) =~ "flowchart BT"
    end

    test ":properties false drops all properties" do
      n = node(0, ["Person"], %{"name" => "Bill"})
      assert Mermaid.flowchart(response([%{"n" => n}]), properties: false) == "flowchart TD\n    n0[\"Person\"]"
    end

    test ":properties list keeps only the named keys, in order" do
      n = node(0, ["Person"], %{"name" => "Bill", "born" => 1949, "secret" => "x"})

      assert Mermaid.flowchart(response([%{"n" => n}]), properties: [:name, :born]) ==
               "flowchart TD\n    n0[\"Person<br/>name: Bill<br/>born: 1949\"]"
    end
  end

  describe "relationships" do
    test "renders a directed edge between two returned nodes" do
      a = node(1, ["Person"], %{})
      b = node(2, ["Movie"], %{})
      r = %Relationship{id: 9, type: "ACTED_IN", start: 1, end: 2}

      assert Mermaid.flowchart(response([%{"a" => a, "r" => r, "b" => b}])) ==
               """
               flowchart TD
                   n1["Person"]
                   n2["Movie"]
                   n1 -->|ACTED_IN| n2\
               """
    end

    test "draws placeholders for endpoints that were not returned" do
      r = %Relationship{id: 9, type: "KNOWS", start: 1, end: 2}
      rendered = Mermaid.flowchart(response([%{"r" => r}]))

      assert rendered =~ ~s(n1["?"])
      assert rendered =~ ~s(n2["?"])
      assert rendered =~ "n1 -->|KNOWS| n2"
    end

    test "de-duplicates identical edges" do
      a = node(1, ["Person"], %{})
      b = node(2, ["Movie"], %{})
      r = %Relationship{id: 9, type: "ACTED_IN", start: 1, end: 2}

      rendered = Mermaid.flowchart(response([%{"a" => a, "r" => r, "b" => b}, %{"a" => a, "r" => r, "b" => b}]))

      assert rendered |> String.split("ACTED_IN") |> length() == 2
    end
  end

  describe "paths" do
    test "renders nodes and direction-correct edges from the traversal sequence" do
      # (n0:Person)-[ACTED_IN]->(n1:Movie): outgoing first hop.
      n0 = node(0, ["Person"], %{"name" => "Bill"})
      n1 = node(1, ["Movie"], %{"title" => "Love Actually"})
      rel = %Bolty.Types.UnboundRelationship{id: 5, type: "ACTED_IN"}
      path = %Path{nodes: [n0, n1], relationships: [rel], sequence: [1, 1]}

      assert Mermaid.flowchart(response([%{"p" => path}])) ==
               """
               flowchart TD
                   n0["Person<br/>name: Bill"]
                   n1["Movie<br/>title: Love Actually"]
                   n0 -->|ACTED_IN| n1\
               """
    end

    test "reverses edge direction for an incoming hop (255 = -1)" do
      n0 = node(0, ["Movie"], %{})
      n1 = node(1, ["Person"], %{})
      rel = %Bolty.Types.UnboundRelationship{id: 5, type: "ACTED_IN"}
      # current=n0, rel_index 255 (-1) means incoming: edge is next -> current.
      path = %Path{nodes: [n0, n1], relationships: [rel], sequence: [255, 1]}

      assert Mermaid.flowchart(response([%{"p" => path}])) =~ "n1 -->|ACTED_IN| n0"
    end
  end

  describe "input shapes and escaping" do
    test "accepts the {:ok, response} tuple" do
      n = node(0, ["Person"], %{})
      assert Mermaid.flowchart({:ok, response([%{"n" => n}])}) == "flowchart TD\n    n0[\"Person\"]"
    end

    test "raises on an error result" do
      assert_raise ArgumentError, ~r/cannot render an error result/, fn ->
        Mermaid.flowchart({:error, :boom})
      end
    end

    test "empty results render a bare flowchart" do
      assert Mermaid.flowchart(response([])) == "flowchart TD"
    end

    test "escapes quotes and angle brackets in label text" do
      n = node(0, [~s(Wei<rd")], %{"k" => "a & b > c"})
      rendered = Mermaid.flowchart(response([%{"n" => n}]))

      assert rendered =~ "Wei&lt;rd&quot;"
      assert rendered =~ "a &amp; b &gt; c"
      refute rendered =~ ~s(rd")
    end

    test "sanitizes string element ids into valid mermaid ids when integer id is absent" do
      n = %Node{id: nil, element_id: "4:abc-def:5", labels: ["X"], properties: %{}}
      assert Mermaid.flowchart(response([%{"n" => n}])) == "flowchart TD\n    n4_abc_def_5[\"X\"]"
    end
  end
end
