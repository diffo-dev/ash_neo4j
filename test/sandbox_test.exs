# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.SandboxTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Neo4jHelper
  alias AshNeo4j.Sandbox

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  describe "isolation" do
    test "nodes created in a test are not visible outside the transaction" do
      Neo4jHelper.create_node([:SandboxTestNode], %{name: "hello"})
      assert {:ok, %{records: [_]}} = Neo4jHelper.read_nodes(:SandboxTestNode, %{name: "hello"})
    end

    test "nodes from the previous test are not visible (rollback worked)" do
      # If the previous test's nodes leaked this would return a non-empty result.
      assert {:ok, %{records: []}} = Neo4jHelper.read_nodes(:SandboxTestNode)
    end

    test "explicit rollback/0 clears writes before the test exits" do
      Neo4jHelper.create_node([:SandboxTestNode], %{name: "to_be_rolled_back"})
      assert {:ok, %{records: [_]}} = Neo4jHelper.read_nodes(:SandboxTestNode, %{name: "to_be_rolled_back"})

      Sandbox.rollback()

      # After explicit rollback the sandbox is gone; the next query uses the pool directly.
      assert {:ok, %{records: []}} = Neo4jHelper.read_nodes(:SandboxTestNode, %{name: "to_be_rolled_back"})
    end

    test "double checkout raises" do
      assert_raise RuntimeError, ~r/already checked out/, fn ->
        Sandbox.checkout()
      end
    end
  end
end
