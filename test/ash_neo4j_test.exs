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
    node = Enum.at(Enum.at(records ,0), 0) |> IO.inspect(label: "read using neo4j")
    assert node.properties == %{"title" => "post1", "uuid" => uuid}
    # read using Ex4j
    results = Ex4j.match_nodes(Node.Post) |> IO.inspect(label: "read using ex4j")
    assert length(results) == 1
    post = results |> Enum.at(0) |> Map.get("Post")
    assert post.title == "post1"
    assert post.uuid == uuid
    # read using Ash
    resource = Ash.read_one!(Post) |> IO.inspect(label: "read using ash")
    assert resource.title == "post1"
    assert resource.id == uuid
  end

  test "node can be read using filter" do
    Neo4j.merge_node(:Post, %{title: "post1"})
    Neo4j.merge_node(:Post, %{title: "post2"})
    # read using Ash
    resources = Ash.read!(Post) |> IO.inspect(label: "read using ash")
    assert length(resources) == 2
    # read using Ash with filter
    result = Post |> Ash.Query.for_read(:read) |> Ash.Query.filter_input([title: [eq: "post2"]]) |> Ash.read!() |> IO.inspect(label: "read using ash with filter")
    assert length(result) == 1
    assert result |> Enum.at(0) |> Map.get(:title) == "post2"
  end

  test "nodes can be created and related" do
    # setup using Neo4j
    Neo4j.relate_nodes(:Post, %{title: "post1"}, :Comment, %{title: "comment1"}, :HAS)
    assert Neo4j.nodes_relate_how?(:Post, %{title: "post1"}, :Comment, %{title: "comment1"}, :HAS)
    # read using Ex4j
    results = Ex4j.match_nodes(Node.Post) |> IO.inspect(label: :match_nodes)
    assert length(results) == 1
    post = results |> Enum.at(0) |> Map.get("Post")
    assert post.title == "post1"

    # read using Ash
    resource = Ash.read_one!(Post) |> IO.inspect(label: :ash_read)
    #resource = Ash.read_one!(Post, load: [:comments]) |> IO.inspect(label: :ash_read)
    assert resource.title == "post1"

    # check comments are loaded
    comments = resource.comments
    assert length(comments) == 1
    assert comments |> Enum.at(0) == "comment1"

    assert [%{title: "post1"}] = Ash.read!(Post)
    assert [%{title: "comment1"}] = Ash.read!(Comment)
  end

  test "filters/sorts can be applied" do
    # setup using Neo4j
    Neo4j.create_node(:Post, %{title: "post1"})
    Neo4j.create_node(:Post, %{title: "post2"})
    Neo4j.create_node(:Post, %{title: "post3"})

    results =
      Post
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(title in ["post1", "post2"])
      |> Ash.Query.sort(:title)
      |> Ash.read!()

    assert length(results) == 2
  end
end
