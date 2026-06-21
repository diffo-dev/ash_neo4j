# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.DynamicLabelsCapabilityTest do
  @moduledoc """
  `BoltyHelper.dynamic_labels?/1` reflects the negotiated `policy().dynamic_labels`
  flag (#339). It is the **server-feature axis** (Neo4j ≥ 5.26, plain Cypher 5),
  distinct from `cypher25?/1` (the `CYPHER 25` language selector, ≥ 2025.06): the
  default 5.26 pool reports `dynamic_labels: true` but `cypher_25: false`.
  """
  alias AshNeo4j.BoltyHelper

  use ExUnit.Case, async: false

  setup_all do
    BoltyHelper.start()
    :ok
  end

  test "default pool (Neo4j 5.26) supports dynamic labels but not Cypher 25" do
    assert BoltyHelper.dynamic_labels?() == true
    assert BoltyHelper.cypher25?() == false
  end

  test "an unstarted pool reports no capability rather than raising" do
    assert BoltyHelper.dynamic_labels?(:no_such_pool) == false
  end

  @tag :bolt6
  test "the Bolt6 pool (Neo4j 2026.05) supports both dynamic labels and Cypher 25" do
    assert BoltyHelper.dynamic_labels?(Bolt6) == true
    assert BoltyHelper.cypher25?(Bolt6) == true
  end
end
