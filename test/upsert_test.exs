# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.UpsertTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Upsert
  alias AshNeo4j.Test.Resource.UpsertPlace

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

    test "create_labels (#392) are added in ON CREATE SET alongside create props" do
      {cypher, _} =
        AshNeo4j.Cypher.Query.upsert_node(
          [:Provider, :GeographicAddress],
          %{key: "k"},
          %{field: "one"},
          %{},
          [:Place]
        )
        |> AshNeo4j.Cypher.render()

      assert cypher ==
               "MERGE (n:Provider:GeographicAddress {key: $n_key}) " <>
                 "ON CREATE SET n += {field: $nc_field}, n:Place RETURN n"
    end

    test "create_labels (#392) emit ON CREATE SET on their own when no create props" do
      {cypher, _} =
        AshNeo4j.Cypher.Query.upsert_node(
          [:Provider, :GeographicAddress],
          %{key: "k"},
          %{},
          %{},
          [:Place, :Telco]
        )
        |> AshNeo4j.Cypher.render()

      assert cypher ==
               "MERGE (n:Provider:GeographicAddress {key: $n_key}) " <>
                 "ON CREATE SET n:Place:Telco RETURN n"
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

    test "upsert-created node carries the fragment base label, like a plain create (#392)" do
      {:ok, _} =
        UpsertPlace
        |> Ash.Changeset.for_create(:create, %{name: "sydney", field: "one"})
        |> Ash.create()

      # The MERGE path must write all_labels, not just label_pair: the :Place
      # fragment label has to be present so base-label reads/relations resolve.
      assert UpsertPlace.__ash_neo4j_mapping__().all_labels == [:SRM, :UpsertPlace, :Place]

      {:ok, %Bolty.Response{results: [%{"labels" => labels}]}} =
        AshNeo4j.Cypher.run(
          "MATCH (n:SRM:UpsertPlace {name: $name}) RETURN labels(n) AS labels",
          %{"name" => "sydney"}
        )

      assert Enum.sort(labels) == ["Place", "SRM", "UpsertPlace"]

      # And the base label alone locates the node (the read/relate path).
      {:ok, %Bolty.Response{results: by_place}} =
        AshNeo4j.Cypher.run("MATCH (n:Place {name: $name}) RETURN n", %{"name" => "sydney"})

      assert length(by_place) == 1
    end

    test "re-upsert through the MERGE path matches the existing node and keeps one node (#392)" do
      {:ok, _} =
        UpsertPlace
        |> Ash.Changeset.for_create(:create, %{name: "perth", field: "one"})
        |> Ash.create()

      {:ok, upsert} =
        UpsertPlace
        |> Ash.Changeset.for_create(:create, %{name: "perth", field: "two"})
        |> Ash.create()

      assert upsert.field == "two"

      results = UpsertPlace |> Ash.Query.for_read(:read) |> Ash.read!()
      assert length(results) == 1
      assert hd(results).field == "two"
    end
  end
end
