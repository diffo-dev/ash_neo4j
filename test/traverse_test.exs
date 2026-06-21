# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.TraverseTest do
  @moduledoc false
  alias AshNeo4j.Functions.Traverse

  use ExUnit.Case, async: true

  test "is a variadic expression function: traverse(chain) | traverse(chain, projection)" do
    assert Traverse.name() == :traverse
    assert [[:any], [:any, :any]] = Traverse.args()
  end

  test "is pushdown-only — no in-memory value" do
    # It needs the graph, so it can't be evaluated from argument values alone.
    assert Traverse.evaluate(%{arguments: [[{:forward, :posts}], :score]}) == :unknown
    assert Traverse.ash_neo4j_pushdown_only?()
  end

  test "is registered with the data layer (parseable in expressions, pushdown accepted)" do
    assert AshNeo4j.Functions.Traverse in AshNeo4j.DataLayer.functions(nil)
    assert AshNeo4j.DataLayer.can?(nil, {:filter_expr, %Traverse{}})
  end
end
