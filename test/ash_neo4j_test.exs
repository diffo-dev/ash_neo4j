defmodule AshNeo4jTest do
  use ExUnit.Case, async: false
  alias AshNeo4j.Test.Neo4j
  alias AshNeo4j.Test.Post
  alias AshNeo4j.Test.Comment
  require Ash.Query

  doctest AshNeo4j.Util
  doctest AshNeo4j.Test.Neo4j

  setup do
    on_exit(fn ->
      Neo4j.delete_all()
    end)
  end

  test "neo4j is running" do
    info = Bolt.Sips.info()
    assert info[:default] != nil
  end

  test "nodes can be created" do
    # setup using Neo4j
    Neo4j.create_node(:Post, %{title: "post1"})
    assert {:ok, %Bolt.Sips.Response{records: records}} = Neo4j.read_node(:Post, %{title: "post1"})
    assert length(records) == 1
    node = Enum.at(Enum.at(records ,0), 0)
    assert node.properties == %{"title" => "post1"}
    # read using Ash
    assert [%{title: "post1"}] = Ash.read!(Post)
  end

  test "nodes can be created and related" do
    # setup using Neo4j
    Neo4j.relate_nodes(:Post, %{title: "post1"}, :Comment, %{title: "comment1"}, :HAS)
    assert Neo4j.nodes_relate_how?(:Post, %{title: "post1"}, :Comment, %{title: "comment1"}, :HAS)
    # read using Ash
    result = Ash.read!(Post)
    assert length(result) == 1
    post_resource = result[0] |> IO.inspect(label: :post_resource)
    assert post_resource.title == "post1"
    comments = post_resource.comments
    assert length(comments) == 1
    assert comments[0] == "comment1"

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
      |> Ash.Query.filter(title in ["post1", "post2"])
      |> Ash.Query.sort(:title)
      |> Ash.read!()

    assert [%{title: "post1"}, %{title: "post2"}] = results
  end
end
