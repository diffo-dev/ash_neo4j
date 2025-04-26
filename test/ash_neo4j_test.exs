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
    create_post_nodes(2)
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
    uuid1 = Ash.UUID.generate()
    uuid2 = Ash.UUID.generate()
    uuid3 = Ash.UUID.generate()
    uuid4 = Ash.UUID.generate()
    uuid5 = Ash.UUID.generate()
    Neo4j.create_node(:Post, %{title: "post1", uuid: uuid1})
    Neo4j.create_node(:Post, %{title: "post2", uuid: uuid2})
    Neo4j.create_node(:Comment, %{title: "comment3", uuid: uuid3})
    Neo4j.create_node(:Comment, %{title: "comment4", uuid: uuid4})
    Neo4j.create_node(:Comment, %{title: "comment5", uuid: uuid5})
    Neo4j.relate_nodes(:Comment, %{uuid: uuid3}, :Post, %{uuid: uuid1}, :BELONGS_TO)
    Neo4j.relate_nodes(:Comment, %{uuid: uuid4}, :Post, %{uuid: uuid1}, :BELONGS_TO)
    Neo4j.relate_nodes(:Comment, %{uuid: uuid5}, :Post, %{uuid: uuid2}, :BELONGS_TO)
    assert Neo4j.nodes_relate_how?(:Comment, %{uuid: uuid3}, :Post, %{uuid: uuid1}, :BELONGS_TO)
    assert Neo4j.nodes_relate_how?(:Comment, %{uuid: uuid4}, :Post, %{uuid: uuid1}, :BELONGS_TO)
    assert Neo4j.nodes_relate_how?(:Comment, %{uuid: uuid5}, :Post, %{uuid: uuid2}, :BELONGS_TO)
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
    create_post_nodes(3)

    results =
      Post
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(title in ["post1", "post2"])
      |> Ash.Query.sort(:title)
      |> Ash.read!()
    assert length(results) == 2
  end

  test "optimised == predicate can be applied" do
    create_post_nodes(3)

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
    create_post_nodes(3)

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
    create_post_nodes(3)

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
    create_post_nodes(3)

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
    create_post_nodes(3)

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
    create_post_nodes(3)

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
    create_post_nodes(3 )

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

  defp create_post_nodes(count) do
    for i <- 1..count do
      Neo4j.create_node(:Post, %{title: "post#{i}", score: i, public: true, uuid: Ash.UUID.generate()})
    end
  end

  defp create_comment_nodes(count) do
    for i <- 1..count do
      Neo4j.create_node(:Comment, %{title: "comment#{i}", uuid: Ash.UUID.generate()})
    end
  end
end
