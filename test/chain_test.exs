# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.ChainTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Neo4jHelper
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Chain
  import AshNeo4j.Test.Util, only: [check_enrichment: 5]

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  describe "Ash Chain tests" do
    test "unchained chain nodes can be created and read using ash" do
      chain1 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain1"}) |> Ash.create!()

      assert chain1.name == "chain1"
      refute chain1.head_id
      refute chain1.tail_id

      chain2 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain2"}) |> Ash.create!()

      assert chain2.name == "chain2"
      results = Chain |> Ash.Query.for_read(:read) |> Ash.read!()
      assert length(results) == 2
      assert hd(results).name == "chain1"
      assert List.last(results).name == "chain2"
    end

    test "chain nodes can be chained tail to head using ash create" do
      chain1 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain1"}) |> Ash.create!()

      assert chain1.name == "chain1"
      refute chain1.head_id
      refute chain1.tail_id

      chain2 =
        Chain
        |> Ash.Changeset.for_create(:create, %{name: "chain2", head_id: chain1.id})
        |> Ash.create!()

      assert Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain1"},
               :Chain,
               %{name: "chain2"},
               :HEAD_TO_TAIL,
               :outgoing
             )

      # check enrichment
      check_enrichment(chain2, :head, Chain, :head_id, chain1.id)
      check_enrichment(chain2, :tail, nil, :tail_id, nil)

      reloaded_chain1 = chain1 |> Ash.load!([:tail, :tail_id])
      check_enrichment(reloaded_chain1, :head, nil, :head_id, nil)
      check_enrichment(reloaded_chain1, :tail, Chain, :tail_id, chain2.id)
    end

    test "chain nodes can be chained head to tail using ash create" do
      chain1 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain1"}) |> Ash.create!()

      chain2 =
        Chain
        |> Ash.Changeset.for_create(:create, %{name: "chain2", tail_id: chain1.id})
        |> Ash.create!()

      assert Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain1"},
               :Chain,
               %{name: "chain2"},
               :HEAD_TO_TAIL,
               :incoming
             )

      # check enrichment
      check_enrichment(chain2, :head, nil, :head_id, nil)
      check_enrichment(chain2, :tail, Chain, :tail_id, chain1.id)

      reloaded_chain1 = chain1 |> Ash.load!([:head, :head_id])
      check_enrichment(reloaded_chain1, :head, Chain, :head_id, chain2.id)
      check_enrichment(reloaded_chain1, :tail, nil, :tail_id, nil)
    end

    test "chain nodes can be looped from same node using ash create" do
      chain1 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain1"}) |> Ash.create!()

      assert chain1.name == "chain1"
      refute chain1.head_id
      refute chain1.tail_id

      chain2 =
        Chain
        |> Ash.Changeset.for_create(:create, %{name: "chain2", tail_id: chain1.id, head_id: chain1.id})
        |> Ash.create!()

      assert Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain2"},
               :Chain,
               %{name: "chain1"},
               :HEAD_TO_TAIL,
               :outgoing
             )

      assert Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain2"},
               :Chain,
               %{name: "chain1"},
               :HEAD_TO_TAIL,
               :incoming
             )

      # check enrichment
      check_enrichment(chain2, :head, Chain, :head_id, chain1.id)
      check_enrichment(chain2, :tail, Chain, :tail_id, chain1.id)

      reloaded_chain1 = chain1 |> Ash.load!([:head, :head_id, :tail, :tail_id])
      check_enrichment(reloaded_chain1, :head, Chain, :head_id, chain2.id)
      check_enrichment(reloaded_chain1, :tail, Chain, :tail_id, chain2.id)
    end

    test "chain nodes can be looped using create and update" do
      chain1 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain1"}) |> Ash.create!()

      assert chain1.name == "chain1"
      refute chain1.head_id
      refute chain1.tail_id

      chain2 =
        Chain
        |> Ash.Changeset.for_create(:create, %{name: "chain2", tail_id: chain1.id})
        |> Ash.create!()

      updated_chain1 =
        chain1
        |> Ash.Changeset.for_update(:update, %{tail_id: chain2.id})
        |> Ash.update!()
        |> Ash.load!([[:tail, :tail_id, :head, :head_id]])

      assert Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain2"},
               :Chain,
               %{name: "chain1"},
               :HEAD_TO_TAIL,
               :outgoing
             )

      assert Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain1"},
               :Chain,
               %{name: "chain2"},
               :HEAD_TO_TAIL,
               :outgoing
             )

      # check enrichment
      check_enrichment(updated_chain1, :head, Chain, :head_id, chain2.id)
      check_enrichment(updated_chain1, :tail, Chain, :tail_id, chain2.id)

      # tail_id shouldn't need an explicit load but it does, seems to be an ash thing
      reloaded_chain2 = chain2 |> Ash.load!([:tail, :tail_id, :head, :head_id])
      check_enrichment(reloaded_chain2, :head, Chain, :head_id, chain1.id)
      check_enrichment(reloaded_chain2, :tail, Chain, :tail_id, chain1.id)
    end

    test "chain nodes can be unlinked using ash update" do
      chain1 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain1"}) |> Ash.create!()
      chain2 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain2", head_id: chain1.id}) |> Ash.create!()

      assert Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain1"},
               :Chain,
               %{name: "chain2"},
               :HEAD_TO_TAIL,
               :outcoming
             )

      updated_chain2 = chain2 |> Ash.Changeset.for_update(:unrelate, %{head_id: chain1.id}) |> Ash.update!()
      refreshed_chain1 = chain1 |> Ash.reload!()

      refute Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain1"},
               :Chain,
               %{name: "chain2"},
               :HEAD_TO_TAIL,
               :outcoming
             )

      # check enrichment
      check_enrichment(refreshed_chain1, :head, nil, :head_id, nil)
      check_enrichment(refreshed_chain1, :tail, nil, :tail_id, nil)

      check_enrichment(updated_chain2, :head, nil, :head_id, nil)
      check_enrichment(updated_chain2, :tail, nil, :tail_id, nil)
    end

    test "chain nodes can be chained head to tail length 3 using ash create" do
      chain3 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain3"}) |> Ash.create!()
      chain2 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain2", tail_id: chain3.id}) |> Ash.create!()
      chain1 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain1", tail_id: chain2.id}) |> Ash.create!()

      refreshed_chain2 = chain2 |> Ash.reload!()
      refreshed_chain3 = chain3 |> Ash.reload!()

      assert Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain1"},
               :Chain,
               %{name: "chain2"},
               :HEAD_TO_TAIL,
               :outgoing
             )

      assert Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain2"},
               :Chain,
               %{name: "chain3"},
               :HEAD_TO_TAIL,
               :outgoing
             )

      # check enrichment
      check_enrichment(chain1, :head, nil, :head_id, nil)
      check_enrichment(chain1, :tail, Chain, :tail_id, chain2.id)

      check_enrichment(refreshed_chain2, :head, Ash.NotLoaded, :head_id, chain1.id)
      check_enrichment(refreshed_chain2, :tail, Ash.NotLoaded, :tail_id, chain3.id)

      check_enrichment(refreshed_chain3, :head, Ash.NotLoaded, :head_id, chain2.id)
      check_enrichment(refreshed_chain3, :tail, nil, :tail_id, nil)
    end

    test "chain can be made with ash create, inserting link into middle" do
      chain1 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain1"}) |> Ash.create!()
      chain3 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain3"}) |> Ash.create!()

      chain2 =
        Chain
        |> Ash.Changeset.for_create(:create, %{name: "chain2", head_id: chain1.id, tail_id: chain3.id})
        |> Ash.create!()

      refreshed_chain1 = chain1 |> Ash.reload!()
      refreshed_chain3 = chain3 |> Ash.reload!()

      assert Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain1"},
               :Chain,
               %{name: "chain2"},
               :HEAD_TO_TAIL,
               :outgoing
             )

      assert Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain2"},
               :Chain,
               %{name: "chain3"},
               :HEAD_TO_TAIL,
               :outgoing
             )

      # check enrichment
      check_enrichment(refreshed_chain1, :head, nil, :head_id, nil)
      check_enrichment(refreshed_chain1, :tail, Ash.NotLoaded, :tail_id, chain2.id)

      check_enrichment(chain2, :head, Chain, :head_id, chain1.id)
      check_enrichment(chain2, :tail, Chain, :tail_id, chain3.id)

      check_enrichment(refreshed_chain3, :head, Ash.NotLoaded, :head_id, chain2.id)
      check_enrichment(refreshed_chain3, :tail, nil, :tail_id, nil)
    end

    test "chain of 3 can be made by updating head and tail on first and last links" do
      chain1 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain1"}) |> Ash.create!()
      chain2 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain2"}) |> Ash.create!()
      chain3 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain3"}) |> Ash.create!()

      updated_chain1 =
        chain1
        |> Ash.Changeset.for_update(:update, tail_id: chain2.id)
        |> Ash.update!()

      updated_chain3 =
        chain3
        |> Ash.Changeset.for_update(:update, head_id: chain2.id)
        |> Ash.update!()

      refreshed_chain2 = chain2 |> Ash.reload!()

      assert Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain1"},
               :Chain,
               %{name: "chain2"},
               :HEAD_TO_TAIL,
               :outgoing
             )

      assert Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain2"},
               :Chain,
               %{name: "chain3"},
               :HEAD_TO_TAIL,
               :outgoing
             )

      # check enrichment
      check_enrichment(updated_chain1, :head, nil, :head_id, nil)
      check_enrichment(updated_chain1, :tail, Chain, :tail_id, chain2.id)

      check_enrichment(refreshed_chain2, :head, Ash.NotLoaded, :head_id, chain1.id)
      check_enrichment(refreshed_chain2, :tail, Ash.NotLoaded, :tail_id, chain3.id)

      check_enrichment(updated_chain3, :head, Chain, :head_id, chain2.id)
      check_enrichment(updated_chain3, :tail, nil, :tail_id, nil)
    end

    test "chain of 3 can be made by updating middle link" do
      chain1 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain1"}) |> Ash.create!()
      chain2 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain2"}) |> Ash.create!()
      chain3 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain3"}) |> Ash.create!()

      # make chain
      updated_chain2 =
        chain2 |> Ash.Changeset.for_update(:update, head_id: chain1.id, tail_id: chain3.id) |> Ash.update!()

      refreshed_chain1 = chain1 |> Ash.reload!()
      refreshed_chain3 = chain3 |> Ash.reload!()

      assert Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain1"},
               :Chain,
               %{name: "chain2"},
               :HEAD_TO_TAIL,
               :outgoing
             )

      assert Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain2"},
               :Chain,
               %{name: "chain3"},
               :HEAD_TO_TAIL,
               :outgoing
             )

      # check enrichment
      check_enrichment(refreshed_chain1, :head, nil, :head_id, nil)
      check_enrichment(refreshed_chain1, :tail, Ash.NotLoaded, :tail_id, chain2.id)

      check_enrichment(updated_chain2, :head, Chain, :head_id, chain1.id)
      check_enrichment(updated_chain2, :tail, Chain, :tail_id, chain3.id)

      check_enrichment(refreshed_chain3, :head, Ash.NotLoaded, :head_id, chain2.id)
      check_enrichment(refreshed_chain3, :tail, nil, :tail_id, nil)
    end

    test "chain of 3 can be broken by updating middle link" do
      chain1 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain1"}) |> Ash.create!()
      chain2 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain2", head_id: chain1.id}) |> Ash.create!()
      chain3 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain3", head_id: chain2.id}) |> Ash.create!()

      assert Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain1"},
               :Chain,
               %{name: "chain2"},
               :HEAD_TO_TAIL,
               :outgoing
             )

      assert Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain2"},
               :Chain,
               %{name: "chain3"},
               :HEAD_TO_TAIL,
               :outgoing
             )

      # break chain
      updated_chain2 =
        chain2
        |> Ash.Changeset.for_update(:unrelate, head_id: chain1.id, tail_id: chain3.id)
        |> Ash.update!()
        |> Ash.load!([:head_id, :tail_id])

      refreshed_chain1 = chain1 |> Ash.reload!()
      refreshed_chain3 = chain3 |> Ash.reload!()

      refute Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain1"},
               :Chain,
               %{name: "chain2"},
               :HEAD_TO_TAIL,
               :outgoing
             )

      refute Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain2"},
               :Chain,
               %{name: "chain3"},
               :HEAD_TO_TAIL,
               :outgoing
             )

      # check enrichment
      check_enrichment(refreshed_chain1, :head, nil, :head_id, nil)
      check_enrichment(refreshed_chain1, :tail, nil, :tail_id, nil)

      check_enrichment(updated_chain2, :head, nil, :head_id, nil)
      check_enrichment(updated_chain2, :tail, nil, :tail_id, nil)

      check_enrichment(refreshed_chain3, :head, nil, :head_id, nil)
      check_enrichment(refreshed_chain3, :tail, nil, :tail_id, nil)
    end

    test "chain of 3 can have a link replaced via update then create" do
      chain1 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain1"}) |> Ash.create!()
      chain2 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain2", head_id: chain1.id}) |> Ash.create!()
      chain3 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain3", head_id: chain2.id}) |> Ash.create!()

      # chain4 replaces chain2
      updated_chain2 =
        chain2 |> Ash.Changeset.for_update(:unrelate, head_id: chain1.id, tail_id: chain3.id) |> Ash.update!()

      chain4 =
        Chain
        |> Ash.Changeset.for_create(:create, %{name: "chain4", head_id: chain1.id, tail_id: chain3.id})
        |> Ash.create!()

      refreshed_chain1 = chain1 |> Ash.reload!()
      refreshed_chain3 = chain3 |> Ash.reload!()

      refute Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain1"},
               :Chain,
               %{name: "chain2"},
               :HEAD_TO_TAIL,
               :outgoing
             )

      refute Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain2"},
               :Chain,
               %{name: "chain3"},
               :HEAD_TO_TAIL,
               :outgoing
             )

      assert Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain1"},
               :Chain,
               %{name: "chain4"},
               :HEAD_TO_TAIL,
               :outgoing
             )

      assert Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain4"},
               :Chain,
               %{name: "chain3"},
               :HEAD_TO_TAIL,
               :outgoing
             )

      # check enrichment
      check_enrichment(refreshed_chain1, :head, nil, :head_id, nil)
      check_enrichment(refreshed_chain1, :tail, Ash.NotLoaded, :tail_id, chain4.id)

      check_enrichment(updated_chain2, :head, nil, :head_id, nil)
      check_enrichment(updated_chain2, :tail, nil, :tail_id, nil)

      check_enrichment(refreshed_chain3, :head, Ash.NotLoaded, :head_id, chain4.id)
      check_enrichment(refreshed_chain3, :tail, nil, :tail_id, nil)

      check_enrichment(chain4, :head, Chain, :head_id, chain1.id)
      check_enrichment(chain4, :tail, Chain, :tail_id, chain3.id)
    end

    test "chain of 3 can have a link replaced via create" do
      chain1 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain1"}) |> Ash.create!()
      chain2 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain2", head_id: chain1.id}) |> Ash.create!()
      chain3 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain3", head_id: chain2.id}) |> Ash.create!()
      # chain4 replaces chain2
      chain4 =
        Chain
        |> Ash.Changeset.for_create(:create, %{name: "chain4", head_id: chain1.id, tail_id: chain3.id})
        |> Ash.create!()

      refreshed_chain1 = chain1 |> Ash.reload!()
      refreshed_chain2 = chain2 |> Ash.reload!()
      refreshed_chain3 = chain3 |> Ash.reload!()

      refute Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain1"},
               :Chain,
               %{name: "chain2"},
               :HEAD_TO_TAIL,
               :outgoing
             )

      refute Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain2"},
               :Chain,
               %{name: "chain3"},
               :HEAD_TO_TAIL,
               :outgoing
             )

      assert Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain1"},
               :Chain,
               %{name: "chain4"},
               :HEAD_TO_TAIL,
               :outgoing
             )

      assert Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain4"},
               :Chain,
               %{name: "chain3"},
               :HEAD_TO_TAIL,
               :outgoing
             )

      # check enrichment
      check_enrichment(refreshed_chain1, :head, nil, :head_id, nil)
      check_enrichment(refreshed_chain1, :tail, Ash.NotLoaded, :tail_id, chain4.id)

      check_enrichment(refreshed_chain2, :head, nil, :head_id, nil)
      check_enrichment(refreshed_chain2, :tail, nil, :tail_id, nil)

      check_enrichment(refreshed_chain3, :head, Ash.NotLoaded, :head_id, chain4.id)
      check_enrichment(refreshed_chain3, :tail, nil, :tail_id, nil)

      check_enrichment(chain4, :head, Chain, :head_id, chain1.id)
      check_enrichment(chain4, :tail, Chain, :tail_id, chain3.id)
    end

    test "chain of 3 can have a link replaced via single update" do
      chain1 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain1"}) |> Ash.create!()
      chain2 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain2", head_id: chain1.id}) |> Ash.create!()
      chain3 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain3", head_id: chain2.id}) |> Ash.create!()
      chain4 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain4"}) |> Ash.create!()
      # chain4 replaces chain2
      updated_chain4 =
        chain4 |> Ash.Changeset.for_update(:update, head_id: chain1.id, tail_id: chain3.id) |> Ash.update!()

      # note reload is needed
      refreshed_chain1 = chain1 |> Ash.reload!()
      refreshed_chain2 = chain2 |> Ash.reload!()
      refreshed_chain3 = chain3 |> Ash.reload!()

      refute Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain1"},
               :Chain,
               %{name: "chain2"},
               :HEAD_TO_TAIL,
               :outgoing
             )

      refute Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain2"},
               :Chain,
               %{name: "chain3"},
               :HEAD_TO_TAIL,
               :outgoing
             )

      assert Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain1"},
               :Chain,
               %{name: "chain4"},
               :HEAD_TO_TAIL,
               :outgoing
             )

      assert Neo4jHelper.nodes_relate_how?(
               :Chain,
               %{name: "chain4"},
               :Chain,
               %{name: "chain3"},
               :HEAD_TO_TAIL,
               :outgoing
             )

      # check enrichment
      check_enrichment(refreshed_chain1, :head, nil, :head_id, nil)
      check_enrichment(refreshed_chain1, :tail, Ash.NotLoaded, :tail_id, chain4.id)

      check_enrichment(refreshed_chain2, :head, nil, :head_id, nil)
      check_enrichment(refreshed_chain2, :tail, nil, :tail_id, nil)

      check_enrichment(refreshed_chain3, :head, Ash.NotLoaded, :head_id, chain4.id)
      check_enrichment(refreshed_chain3, :tail, nil, :tail_id, nil)

      check_enrichment(updated_chain4, :head, Chain, :head_id, chain1.id)
      check_enrichment(updated_chain4, :tail, Chain, :tail_id, chain3.id)
    end
  end
end
