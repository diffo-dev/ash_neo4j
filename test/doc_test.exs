# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.DocTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Neo4jHelper
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Cypher
  alias AshNeo4j.Util

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  describe "doctests" do
    doctest BoltyHelper
    doctest Neo4jHelper
    doctest Cypher
    doctest Util
  end
end
