defmodule AshNeo4jTest do
  use ExUnit.Case, async: false
  alias AshNeo4j.Neo4j.Helper, as: Neo4j
  alias AshNeo4j.Ex4j.Helper, as: Ex4j
  alias AshNeo4j.Test.Resource.Post
  alias AshNeo4j.Test.Resource.Comment
  require Ash.Query
  require Node.Post

  doctest AshNeo4j.Util
  doctest AshNeo4j.Neo4j.Helper

  setup do
    on_exit(fn ->
      Neo4j.delete_all()
    end)
  end

  test "neo4j is running" do
    info = Bolt.Sips.info()
    assert info[:default] != nil
  end

  test "node can be read" do
    # setup using Neo4j
    uuid = Ash.UUID.generate()
    Neo4j.create_node(:Post, %{title: "post1", uuid: uuid})
    assert {:ok, %Bolt.Sips.Response{records: records}} = Neo4j.read_node(:Post, %{title: "post1"})
    assert length(records) == 1
    node = Enum.at(Enum.at(records ,0), 0)
    assert node.properties == %{"title" => "post1", "uuid" => uuid}
    # read using Ex4j
    results = Ex4j.match_nodes(Node.Post)
    assert length(results) == 1
    post = results |> Enum.at(0) |> Map.get("Post")
    assert post.title == "post1"
    assert post.uuid == uuid
    # read using Ash
    resource = Ash.read_one!(Post)
    assert resource.title == "post1"
    assert resource.id == uuid
  end

  test "node can be read using filter" do
    Neo4j.merge_node(:Post, %{title: "post1"})
    Neo4j.merge_node(:Post, %{title: "post2"})
    # read using Ash
    resources = Ash.read!(Post)
    assert length(resources) == 2
    # read using Ash with filter
    result = Post |> Ash.Query.for_read(:read) |> Ash.Query.filter_input([title: [eq: "post2"]]) |> Ash.read!()
    assert length(result) == 1
    assert result |> Enum.at(0) |> Map.get(:title) == "post2"
  end

  #TODO test fails, need to handle load of related node
  test "nodes can be created and related" do
    # setup using Neo4j
    Neo4j.relate_nodes(:Comment, %{title: "comment1"}, :Post, %{title: "post1"}, :BELONGS_TO)
    Neo4j.relate_nodes(:Comment, %{title: "comment2"}, :Post, %{title: "post1"}, :BELONGS_TO)
    Neo4j.relate_nodes(:Comment, %{title: "comment3"}, :Post, %{title: "post2"}, :BELONGS_TO)
    assert Neo4j.nodes_relate_how?(:Comment, %{title: "comment1"}, :Post, %{title: "post1"}, :BELONGS_TO)
    # read using Ex4j
    results = Ex4j.match_nodes(Node.Post)
    assert length(results) == 2
    results = Ex4j.match_nodes(Node.Comment)
    assert length(results) == 3

    # read using Ash, loading related comments
    result = Post |> Ash.Query.for_read(:read) |> Ash.Query.filter_input([title: [eq: "post2"]]) |> Ash.read!() |> IO.inspect(label: :ash_read)
    assert length(result.comments) == 1

    result = Post |> Ash.Query.for_read(:read) |> Ash.Query.filter_input([title: [eq: "post1"]]) |> Ash.read!() |> IO.inspect(label: :ash_read)
    assert length(result.comments) == 2

  end

  test "filters/sorts can be applied" do
    # setup using Neo4j
    Neo4j.create_node(:Post, %{title: "post1", score: 1, public: true})
    Neo4j.create_node(:Post, %{title: "post2", score: 2, public: true})
    Neo4j.create_node(:Post, %{title: "post3", score: 3, public: false})

    results =
      Post
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(title in ["post1", "post2"])
      |> Ash.Query.sort(:title)
      |> Ash.read!()
    assert length(results) == 2
  end

  test "optimised == predicate can be applied" do
    # setup using Neo4j
    Neo4j.create_node(:Post, %{title: "post1", score: 1, public: true})
    Neo4j.create_node(:Post, %{title: "post2", score: 2, public: true})
    Neo4j.create_node(:Post, %{title: "post3", score: 3, public: false})

    results =
      Post
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(title == "post2")
      |> Ash.read!()
    assert length(results) == 1

    results =
      Post
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(score == 2)
      |> Ash.read!()
    assert length(results) == 1
  end

  test "optimised != predicate can be applied" do
    # setup using Neo4j
    Neo4j.create_node(:Post, %{title: "post1", score: 1, public: true})
    Neo4j.create_node(:Post, %{title: "post2", score: 2, public: true})
    Neo4j.create_node(:Post, %{title: "post3", score: 3, public: false})

    results =
      Post
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(title != "post2")
      |> Ash.read!()
    assert length(results) == 2

    results =
      Post
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(score != 2)
      |> Ash.read!()
    assert length(results) == 2
  end

  test "optimised in predicate can be applied" do
    # setup using Neo4j

    Neo4j.create_node(:Post, %{title: "post1", score: 1, public: true})
    Neo4j.create_node(:Post, %{title: "post2", score: 2, public: true})
    Neo4j.create_node(:Post, %{title: "post3", score: 3, public: false})

    results =
      Post
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(title in ["post2", "post3"])
      |> Ash.read!()
    assert length(results) == 2

    results =
      Post
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(score in [1, 2])
      |> Ash.read!()
    assert length(results) == 2
  end

  test "optimised > predicate can be applied" do
    # setup using Neo4j
    Neo4j.create_node(:Post, %{title: "post1", score: 1, public: true})
    Neo4j.create_node(:Post, %{title: "post2", score: 2, public: true})
    Neo4j.create_node(:Post, %{title: "post3", score: 3, public: false})

    results =
      Post
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(title > "post1")
      |> Ash.read!()
    assert length(results) == 2

    results =
      Post
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(score > 1)
      |> Ash.read!()
    assert length(results) == 2
  end

  test "optimised >= predicate can be applied" do
    # setup using Neo4j
    Neo4j.create_node(:Post, %{title: "post1", score: 1, public: true})
    Neo4j.create_node(:Post, %{title: "post2", score: 2, public: true})
    Neo4j.create_node(:Post, %{title: "post3", score: 3, public: false})

    results =
      Post
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(title >= "post2")
      |> Ash.read!()
    assert length(results) == 2

    results =
      Post
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(score >= 2)
      |> Ash.read!()
    assert length(results) == 2
  end

  test "optimised < predicate can be applied" do
    # setup using Neo4j
    Neo4j.create_node(:Post, %{title: "post1", score: 1, public: true})
    Neo4j.create_node(:Post, %{title: "post2", score: 2, public: true})
    Neo4j.create_node(:Post, %{title: "post3", score: 3, public: false})

    results =
      Post
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(title < "post2")
      |> Ash.read!()
    assert length(results) == 1

    results =
      Post
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(score < 3)
      |> Ash.read!()
    assert length(results) == 2
  end

  test "optimised <= predicate can be applied" do
    # setup using Neo4j
    Neo4j.create_node(:Post, %{title: "post1", score: 1, public: true})
    Neo4j.create_node(:Post, %{title: "post2", score: 2, public: true})
    Neo4j.create_node(:Post, %{title: "post3", score: 3, public: false})

    results =
      Post
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(title <= "post2")
      |> Ash.read!()
    assert length(results) == 2

    results =
      Post
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(score <= 2)
      |> Ash.read!()
    assert length(results) == 2
  end
end
