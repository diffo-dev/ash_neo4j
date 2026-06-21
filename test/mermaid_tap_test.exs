# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.MermaidTapTest do
  @moduledoc """
  Tests for the live tap (`tap/0` / `last/1` / `untap/0`). Drives the
  `[:ash_neo4j, :query]` telemetry seam directly — no Neo4j connection — and
  runs sync because the handler and stash Agent are process-global state.
  """
  use ExUnit.Case, async: false

  alias AshNeo4j.Mermaid
  alias Bolty.Response
  alias Bolty.Types.Node

  setup do
    on_exit(&Mermaid.untap/0)
    :ok
  end

  defp emit(result) do
    :telemetry.execute([:ash_neo4j, :query], %{duration: 1}, %{cypher: "…", params: %{}, result: result})
  end

  defp ok_node(id, labels, properties \\ %{}) do
    {:ok, %Response{results: [%{"n" => %Node{id: id, labels: labels, properties: properties}}]}}
  end

  test "captures the last successful result and last/1 renders it" do
    Mermaid.tap()
    emit(ok_node(0, ["Person"], %{"name" => "Bill"}))

    assert Mermaid.last() == "flowchart TD\n    n0[\"Person<br/>name: Bill\"]"
  end

  test "last/1 reflects only the most recent result" do
    Mermaid.tap()
    emit(ok_node(0, ["Person"]))
    emit(ok_node(9, ["Movie"]))

    assert Mermaid.last() == "flowchart TD\n    n9[\"Movie\"]"
  end

  test "last/1 forwards options to flowchart/2" do
    Mermaid.tap()
    emit(ok_node(0, ["Person"], %{"name" => "Bill"}))

    assert Mermaid.last(properties: false) == "flowchart TD\n    n0[\"Person\"]"
  end

  test "tap/0 is idempotent" do
    assert Mermaid.tap() == :ok
    assert Mermaid.tap() == :ok
    emit(ok_node(0, ["Person"]))
    assert Mermaid.last() == "flowchart TD\n    n0[\"Person\"]"
  end

  test "error results are not captured" do
    Mermaid.tap()
    emit(ok_node(0, ["Person"]))
    emit({:error, :boom})

    assert Mermaid.last() == "flowchart TD\n    n0[\"Person\"]"
  end

  test "scalar-only results don't clobber the last graph view" do
    Mermaid.tap()
    emit(ok_node(0, ["Person"]))
    emit({:ok, %Response{results: [%{"count" => 5}]}})

    assert Mermaid.last() == "flowchart TD\n    n0[\"Person\"]"
  end

  test "nothing is captured until a graph result arrives" do
    Mermaid.tap()
    emit({:ok, %Response{results: [%{"count" => 5}]}})

    assert_raise RuntimeError, ~r/nothing captured/, fn -> Mermaid.last() end
  end

  test "untap/0 stops capture and clears the stash" do
    Mermaid.tap()
    emit(ok_node(0, ["Person"]))
    Mermaid.untap()
    emit(ok_node(9, ["Movie"]))

    assert_raise RuntimeError, ~r/nothing captured/, fn -> Mermaid.last() end
  end

  test "untap/0 is idempotent" do
    assert Mermaid.untap() == :ok
    assert Mermaid.untap() == :ok
  end

  test "last/1 raises when nothing has been captured" do
    assert_raise RuntimeError, ~r/call AshNeo4j.Mermaid.tap/, fn -> Mermaid.last() end
  end
end
