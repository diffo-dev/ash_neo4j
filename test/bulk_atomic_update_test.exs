# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.BulkAtomicUpdateTest do
  @moduledoc """
  Bulk atomic update (#361): `Ash.bulk_update` with the `:atomic` strategy applies
  the action's `changeset.atomics` to every node matching the query in a single
  `MATCH (n:L) WHERE <query filter> SET … RETURN n` — via `update_query/4`.
  """
  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Comment

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

  test "increments score atomically for every node matching the query filter" do
    for score <- [1, 5, 50, 200], do: Comment |> Ash.create!(%{title: "t", score: score})

    result =
      Comment
      |> Ash.Query.filter(score < 100)
      |> Ash.bulk_update!(:increment_score, %{},
        strategy: :atomic,
        return_records?: true,
        return_errors?: true
      )

    assert result.status == :success
    assert result.records |> Enum.map(& &1.score) |> Enum.sort() == [2, 6, 51]

    # The out-of-scope node (200) is untouched.
    assert Comment |> Ash.Query.filter(score == 200) |> Ash.read_one!() |> Map.get(:score) == 200
  end

  test "an unfiltered bulk atomic update touches every node of the label" do
    for score <- [10, 20, 30], do: Comment |> Ash.create!(%{title: "t", score: score})

    result =
      Comment
      |> Ash.bulk_update!(:increment_score, %{}, strategy: :atomic, return_records?: true)

    assert result.records |> Enum.map(& &1.score) |> Enum.sort() == [11, 21, 31]
  end
end
