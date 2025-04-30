defmodule AshNeo4jTest do
  use ExUnit.Case, async: false
  alias AshNeo4j.Neo4jHelper
  alias AshNeo4j.Test.Resource.Post
  alias AshNeo4j.Test.Resource.Comment
  require Ash.Query

  doctest AshNeo4j.Neo4jHelper
  doctest AshNeo4j.QueryHelper

  setup_all do
    {result, _} = Boltx.start_link(Application.get_env(:boltx, Bolt))
    result
  end

  setup do
    on_exit(fn ->
      Neo4jHelper.delete_all()
    end)
  end

  test "neo4j is running" do
    assert Boltx.query!(Bolt, "return 1 as n") |> Boltx.Response.first() == %{"n" => 1}
  end

  test "post node can be read using Neo4jHelper" do
    # setup using Neo4jHelper
    uuid = Ash.UUID.generate()
    Neo4jHelper.create_node(:Post, %{title: "post1", uuid: uuid})
    # read using Neo4jHelper
    assert {:ok, %{records: records}} = Neo4jHelper.read_nodes(:Post, %{title: "post1"})
    assert length(records) == 1
    node = records |> List.first() |> List.first()
    assert node.labels == ["Post"]
    assert node.properties == %{"title" => "post1", "uuid" => uuid}
    # read all using Neo4jHelper
    assert {:ok, %{records: records}} = Neo4jHelper.read_nodes(:Post)
    assert length(records) == 1
    node = records |> List.first() |> List.first()
    assert node.labels == ["Post"]
    assert node.properties == %{"title" => "post1", "uuid" => uuid}
  end

  test "comment node can be read using Neo4jHelper" do
    # setup using Neo4jHelper
    uuid = Ash.UUID.generate()
    Neo4jHelper.create_node(:Comment, %{title: "comment1", uuid: uuid})
    # read using Neo4jHelper
    assert {:ok, %{records: records}} = Neo4jHelper.read_nodes(:Comment, %{title: "comment1"})
    assert length(records) == 1
    node = records |> List.first() |> List.first()
    assert node.labels == ["Comment"]
    assert node.properties == %{"title" => "comment1", "uuid" => uuid}
    # read all using Neo4jHelper
    assert {:ok, %{records: records}} = Neo4jHelper.read_nodes(:Comment)
    assert length(records) == 1
    node = records |> List.first() |> List.first()
    assert node.labels == ["Comment"]
    assert node.properties == %{"title" => "comment1", "uuid" => uuid}
  end

  test "post node can be read using ash" do
    create_post_nodes(2)
    # read using Ash
    resources = Ash.read!(Post)
    assert length(resources) == 2
    # read using Ash with filter
    result = Post |> Ash.Query.for_read(:read) |> Ash.Query.filter_input([title: [eq: "post2"]]) |> Ash.read!()
    #|> IO.inspect(label: :post_node)
    assert length(result) == 1
    assert result |> Enum.at(0) |> Map.get(:title) == "post2"
  end

  test "comment node can be read using ash" do
    create_comment_nodes(2)
    # read using Ash
    resources = Ash.read!(Comment)
    assert length(resources) == 2
    # read using Ash with filter
    result = Comment |> Ash.Query.for_read(:read) |> Ash.Query.filter_input([title: [eq: "comment2"]]) |> Ash.read!()
    #|> IO.inspect(label: :comment_node)
    assert length(result) == 1
    assert result |> Enum.at(0) |> Map.get(:title) == "comment2"
  end

  test "nodes can be created and related" do
    # setup using Neo4jHelper
    uuid1 = Ash.UUID.generate()
    uuid2 = Ash.UUID.generate()
    uuid3 = Ash.UUID.generate()
    uuid4 = Ash.UUID.generate()
    uuid5 = Ash.UUID.generate()
    Neo4jHelper.create_node(:Post, %{title: "post1", uuid: uuid1})
    Neo4jHelper.create_node(:Post, %{title: "post2", uuid: uuid2})
    Neo4jHelper.create_node(:Comment, %{title: "comment3", uuid: uuid3})
    Neo4jHelper.create_node(:Comment, %{title: "comment4", uuid: uuid4})
    Neo4jHelper.create_node(:Comment, %{title: "comment5", uuid: uuid5})
    Neo4jHelper.relate_nodes(:Comment, %{uuid: uuid3}, :Post, %{uuid: uuid1}, :BELONGS_TO)
    Neo4jHelper.relate_nodes(:Comment, %{uuid: uuid4}, :Post, %{uuid: uuid1}, :BELONGS_TO)
    Neo4jHelper.relate_nodes(:Comment, %{uuid: uuid5}, :Post, %{uuid: uuid2}, :BELONGS_TO)
    assert Neo4jHelper.nodes_relate_how?(:Comment, %{uuid: uuid3}, :Post, %{uuid: uuid1}, :BELONGS_TO)
    assert Neo4jHelper.nodes_relate_how?(:Comment, %{uuid: uuid4}, :Post, %{uuid: uuid1}, :BELONGS_TO)
    assert Neo4jHelper.nodes_relate_how?(:Comment, %{uuid: uuid5}, :Post, %{uuid: uuid2}, :BELONGS_TO)

    # read Post using Ash, loading related comments
    result = Post |> Ash.Query.for_read(:read) |> Ash.Query.load([:comments]) |> Ash.Query.filter_input([title: [eq: "post2"]]) |> Ash.read_one!()
    #|> IO.inspect(label: "ash read post2 loading comments")
    assert length(result.comments) == 1

    result = Post |> Ash.Query.for_read(:read) |> Ash.Query.load([:comments]) |> Ash.Query.filter_input([title: [eq: "post1"]]) |> Ash.read_one!()
    #|> IO.inspect(label: "ash read post1 loading comments")
    assert length(result.comments) == 2

    # read Comments using Ash, loading related Post
    result = Comment |> Ash.Query.for_read(:read) |> Ash.Query.load([:post]) |> Ash.Query.filter_input([title: [eq: "comment3"]]) |> Ash.read_one!()
    #|> IO.inspect(label: "ash read comment3 loading post")
    assert result.post != nil
    assert result.post |> Map.get(:title) == "post1"

    result = Comment |> Ash.Query.for_read(:read) |> Ash.Query.load([:post]) |> Ash.Query.filter_input([title: [eq: "comment4"]]) |> Ash.read_one!()
    #|> IO.inspect(label: "ash read comment4 loading post")
    assert result.post != nil
    assert result.post |> Map.get(:title) == "post1"

    result = Comment |> Ash.Query.for_read(:read) |> Ash.Query.load([:post]) |> Ash.Query.filter_input([title: [eq: "comment5"]]) |> Ash.read_one!()
    #|> IO.inspect(label: "ash read comment4 loading post")
    assert result.post != nil
    assert result.post |> Map.get(:title) == "post2"
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
      Neo4jHelper.create_node(:Post, %{title: "post#{i}", score: i, public: true, uuid: Ash.UUID.generate()})
    end
  end

  defp create_comment_nodes(count) do
    for i <- 1..count do
      Neo4jHelper.create_node(:Comment, %{title: "comment#{i}", uuid: Ash.UUID.generate()})
    end
  end
end
