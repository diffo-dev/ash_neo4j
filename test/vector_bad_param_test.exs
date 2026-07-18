# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.VectorBadParamTest do
  @moduledoc """
  A `vector_similarity` / `vector_cosine_distance` query embedding that isn't a
  list of numbers or a `%Bolty.Types.Vector{}` returns (never raises)
  `{:error, %AshNeo4j.Error.UnsupportedVectorParam{}}` (#412).

  Tagged `:cypher25` and routed to the `Bolt6` pool (Neo4j 2026.05) because the
  builder checks `require_cypher25/0` first — on a non-Cypher-25 server that
  check short-circuits before the embedding is ever converted, so the bad-param
  path is only reachable when Cypher 25 is available.
  """
  use ExUnit.Case, async: false

  require Ash.Query
  import Ash.Expr

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Error.UnsupportedVectorParam
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.ThingNote

  @moduletag :cypher25

  setup_all do
    BoltyHelper.start()
    :ok
  end

  setup do
    Process.put(:ash_neo4j_pool, Bolt6)
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
    :ok
  end

  defp flatten(%{errors: errors}) when is_list(errors), do: Enum.flat_map(errors, &flatten/1)
  defp flatten(e), do: [e]

  test "a vector_similarity filter with a non-vector embedding returns a typed error, not a raise" do
    {:error, error} =
      ThingNote
      |> Ash.Query.filter(vector_similarity(embedding, ^"oops") > 0.5)
      |> Ash.read()

    assert Enum.any?(flatten(error), &match?(%UnsupportedVectorParam{}, &1))
  end

  test "a vector_cosine_distance sort with a non-vector embedding returns a typed error, not a raise" do
    {:error, error} =
      ThingNote
      |> Ash.Query.sort({calc(vector_cosine_distance(embedding, ^"oops"), type: :float), :asc})
      |> Ash.read()

    assert Enum.any?(flatten(error), &match?(%UnsupportedVectorParam{}, &1))
  end
end
