# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.UpsertTest do
  @moduledoc false
  use ExUnit.Case
  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Neo4jHelper
  alias AshNeo4j.Test.Resource.Upsert

  setup_all do
    BoltyHelper.start()
  end

  setup do
    on_exit(fn ->
      Neo4jHelper.delete_nodes(:Upsert)
    end)
  end

  describe "Ash Upsert tests" do
    test "upsert node can be upserted using ash" do
      {:ok, upsert} =
        Upsert
        |> Ash.Changeset.for_create(:create, %{first_name: "Donald", surname: "Duck", field: "one"})
        |> Ash.create()

      assert upsert.field == "one"

      {:ok, upsert} =
        Upsert
        |> Ash.Changeset.for_create(:create, %{first_name: "Donald", surname: "Duck", field: "two"})
        |> Ash.create()

      assert upsert.field == "two"
      results = Upsert |> Ash.Query.for_read(:read) |> Ash.read!()
      assert length(results) == 1
      assert hd(results).field == "two"
    end
  end
end
