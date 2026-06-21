# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.UpsertTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Upsert

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  describe "upsert_node render (#379)" do
    test "MERGE on the identity, ON CREATE/ON MATCH SET, distinct param prefixes" do
      query =
        AshNeo4j.Cypher.Query.upsert_node(
          :Upsert,
          %{firstName: "Donald"},
          %{field: "one"},
          %{field: "two"}
        )

      {cypher, params} = AshNeo4j.Cypher.render(query)

      assert cypher ==
               "MERGE (n:Upsert {firstName: $n_firstName}) " <>
                 "ON CREATE SET n += {field: $nc_field} " <>
                 "ON MATCH SET n += {field: $nm_field} RETURN n"

      # Distinct prefixes (n_/nc_/nm_) so the three property sets don't collide.
      assert params == %{"n_firstName" => "Donald", "nc_field" => "one", "nm_field" => "two"}
    end

    test "omits ON CREATE / ON MATCH when their property sets are empty" do
      {cypher, _} =
        AshNeo4j.Cypher.Query.upsert_node(:Upsert, %{firstName: "Donald"}, %{}, %{})
        |> AshNeo4j.Cypher.render()

      assert cypher == "MERGE (n:Upsert {firstName: $n_firstName}) RETURN n"
    end
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
