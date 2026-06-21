# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.VectorRequiresCypher25Test do
  @moduledoc """
  Vector operations against a non-Cypher-25 server return (never raise)
  `{:error, %AshNeo4j.Error.RequiresCypher25{}}` (#350). These run on the
  **default** pool (Neo4j 5.x, no Cypher 25), so the requirement is unmet.
  """
  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Error.RequiresCypher25
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.ThingNote
  alias AshNeo4j.Vector

  use ExUnit.Case, async: false

  require Ash.Query

  setup_all do
    BoltyHelper.start()
    :ok
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  defp flatten(%{errors: errors} = e) when is_list(errors), do: [e | Enum.flat_map(errors, &flatten/1)]
  defp flatten(e), do: [e]

  defp requires_cypher25?(error), do: error |> flatten() |> Enum.any?(&match?(%RequiresCypher25{}, &1))

  test "a vector_similarity filter returns RequiresCypher25, not a raise" do
    {:error, error} =
      ThingNote
      |> Ash.Query.filter(vector_similarity(embedding, ^[1.0, 0.0, 0.0]) > 0.5)
      |> Ash.read()

    assert requires_cypher25?(error)
  end

  test "create_index returns {:error, RequiresCypher25}" do
    assert {:error, %RequiresCypher25{}} = Vector.create_index(ThingNote, :embedding)
  end

  test "drop_index returns {:error, RequiresCypher25}" do
    assert {:error, %RequiresCypher25{}} = Vector.drop_index(ThingNote, :embedding)
  end
end
