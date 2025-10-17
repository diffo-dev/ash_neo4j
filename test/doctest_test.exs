# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Doc do
  @moduledoc false
  use ExUnit.Case
  alias AshNeo4j.BoltxHelper
  alias AshNeo4j.Neo4jHelper
  alias AshNeo4j.Cypher

  setup_all do
    BoltxHelper.start()
  end

  setup do
    on_exit(fn ->
      Neo4jHelper.delete_all()
    end)
  end

  describe "doctests" do
    doctest BoltxHelper
    doctest Neo4jHelper
    doctest Cypher
  end
end
