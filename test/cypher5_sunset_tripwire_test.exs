# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Cypher5SunsetTripwireTest do
  @moduledoc """
  The CYPHER 5 sunset tripwire (#363): when AshNeo4j emits unprefixed Cypher (the
  Neo4j 5.26-LTS fallback, taken when the server isn't a Cypher 25 server) against
  a server that reports no CYPHER 5 support (`policy.cypher_5 == false`), it warns
  once per pool rather than emit silently. CYPHER 5 is feature-capped from Neo4j
  2026.06 and slated for removal.
  """
  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Cypher
  alias AshNeo4j.Cypher.{Match, Query, Return}

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  setup_all do
    BoltyHelper.start()
    :ok
  end

  defp simple_query do
    %Query{clauses: [%Match{pattern: "(s:Place)"}, %Return{items: ["s"]}], params: %{}}
  end

  describe "a server with no CYPHER 5 and no Cypher 25 (the stranded sunset state)" do
    setup do
      pool = :tripwire_fake_pool
      :persistent_term.put({BoltyHelper, :policy, pool}, %Bolty.Policy{cypher_5: false, cypher_25: false})

      on_exit(fn ->
        :persistent_term.erase({BoltyHelper, :policy, pool})
        :persistent_term.erase({Cypher, :cypher5_warned, pool})
      end)

      %{pool: pool}
    end

    test "warns on a bare-fallback render", %{pool: pool} do
      log =
        capture_log(fn ->
          BoltyHelper.with_pool(pool, fn -> Cypher.render(simple_query()) end)
        end)

      assert log =~ "CYPHER 5 fallback"
      assert log =~ "policy.cypher_5 == false"
    end

    test "warns at most once per pool", %{pool: pool} do
      log =
        capture_log(fn ->
          BoltyHelper.with_pool(pool, fn ->
            Cypher.render(simple_query())
            Cypher.render(simple_query())
            Cypher.render(simple_query())
          end)
        end)

      assert log |> String.split("CYPHER 5 fallback") |> length() == 2
    end
  end

  test "no warning on the default 5.26 pool (cypher_5 true)" do
    log = capture_log(fn -> Cypher.render(simple_query()) end)
    refute log =~ "CYPHER 5 fallback"
  end
end
