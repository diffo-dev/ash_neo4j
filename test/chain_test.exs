defmodule AshNeo4j.Test.Chain do
  @moduledoc false
  use ExUnit.Case
  alias AshNeo4j.BoltxHelper
  alias AshNeo4j.Neo4jHelper
  alias AshNeo4j.Test.Resource.Chain

  setup_all do
    BoltxHelper.start()
  end

  setup do
    on_exit(fn ->
      Neo4jHelper.delete_nodes(:Chain)
    end)
  end

  describe "Ash Chain tests" do
    test "unchained chain nodes can be created and read using ash" do
      chain1 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain1"})|> Ash.create!()

      assert chain1.name == "chain1"
      refute chain1.head_id
      refute chain1.tail_id


      chain2 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain2"}) |> Ash.create!()

      assert chain2.name == "chain2"
      results = Chain |> Ash.Query.for_read(:read) |> Ash.read!()
      assert length(results) == 2
      assert hd(results).name == "chain2"
    end

    test "chain nodes can be chained tail to head using ash create" do
      chain1 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain1"})|> Ash.create!()

      assert chain1.name == "chain1"
      refute chain1.head_id
      refute chain1.tail_id

      chain2 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain2", head_id: chain1.id}) |> Ash.create!()

      assert chain2.name == "chain2"
      assert chain2.head_id == chain1.id
      refute chain2.tail_id
      assert is_struct(chain2.head, Chain)
      assert chain2.head.id == chain1.id

      loaded_chain1 = chain1 |> Ash.load!([:tail, :tail_id])

      assert loaded_chain1.tail_id == chain2.id
      refute loaded_chain1.head_id
      assert is_struct(loaded_chain1.tail, Chain)
      assert loaded_chain1.tail.id == chain2.id

      assert Neo4jHelper.nodes_relate_how?(
          :Chain,
          %{name: "chain1"},
          :Chain,
          %{name: "chain2"},
          :HEAD_TO_TAIL,
          :outgoing
        )
    end
  end

  test "chain nodes can be chained head to tail using ash create" do
    chain2 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain2"})|> Ash.create!()

    assert chain2.name == "chain2"
    refute chain2.head_id
    refute chain2.tail_id

    chain1 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain1", tail_id: chain2.id}) |> Ash.create!()

    assert chain1.name == "chain1"
    assert chain1.tail_id == chain2.id
    refute chain1.head_id
    assert is_struct(chain1.tail, Chain)
    assert chain1.tail.id == chain2.id

    loaded_chain2 = chain2 |> Ash.load!([:head, :tail, :head_id, :tail_id])

    assert loaded_chain2.head_id == chain1.id
    refute loaded_chain2.tail_id
    assert is_struct(loaded_chain2.head, Chain)
    assert loaded_chain2.head.id == chain1.id

    assert Neo4jHelper.nodes_relate_how?(
        :Chain,
        %{name: "chain1"},
        :Chain,
        %{name: "chain2"},
        :HEAD_TO_TAIL,
        :outgoing
      )
  end

  test "chain nodes can be chained head to tail length 3 using ash create" do
    chain3 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain3"})|> Ash.create!()

    assert chain3.name == "chain3"
    refute chain3.head_id
    refute chain3.tail_id

    chain2 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain2", tail_id: chain3.id})|> Ash.create!()

    assert chain2.name == "chain2"
    assert chain2.tail_id == chain3.id
    refute chain2.head_id
    assert is_struct(chain2.tail, Chain)
    assert chain2.tail.id == chain3.id
    assert is_struct(chain2.head, Ash.NotLoaded)

    chain1 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain1", tail_id: chain2.id}) |> Ash.create!()

    assert chain1.name == "chain1"
    assert chain1.tail_id == chain2.id
    refute chain1.head_id
    assert is_struct(chain1.tail, Chain)
    assert chain1.tail.id == chain2.id
    assert is_struct(chain1.head, Ash.NotLoaded)

    loaded_chain3 = chain3 |> Ash.load!([:head, :tail])

    assert loaded_chain3.head_id == chain2.id
    refute loaded_chain3.tail_id
    assert is_struct(loaded_chain3.head, Chain)
    assert loaded_chain3.head.id == chain2.id
    refute loaded_chain3.tail

    loaded_chain2 = chain2 |> Ash.load!([:head, :tail])

    assert loaded_chain2.head_id == chain1.id
    assert loaded_chain2.tail_id == chain3.id
    assert is_struct(loaded_chain2.head, Chain)
    assert loaded_chain2.head.id == chain1.id
    assert is_struct(loaded_chain2.tail, Chain)
    assert loaded_chain2.tail.id == chain3.id

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
  end

  test "chain can be made with ash create, inserting link into middle" do
    chain1 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain1"})|> Ash.create!()
    chain3 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain3"})|> Ash.create!()
    _chain2 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain2", head_id: chain1.id, tail_id: chain3.id})|> Ash.create!()

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
  end

  @tag bugged: true # fails to relate nodes, ash issues a query with id in [nil]
  test "chain of 3 can be made by updating head and tail on first and last links" do
    chain1 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain1"})|> Ash.create!()
    chain2 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain2"})|> Ash.create!()
    chain3 = Chain |> Ash.Changeset.for_create(:create, %{name: "chain3"})|> Ash.create!()

    _updated_chain1 = chain1 |> Ash.Changeset.for_update(:update, tail_id: chain2.id)|> Ash.update!()
    _updated_chain3 = chain3 |> Ash.Changeset.for_update(:update, head_id: chain2.id)|> Ash.update!()

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
  end
end
