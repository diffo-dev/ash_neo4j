defmodule AshNeo4j.Test do
  use ExUnit.Case, async: false
  alias AshNeo4j.Neo4jHelper
  alias AshNeo4j.Test.Resource.Type
  alias AshNeo4j.Test.Resource.Post
  alias AshNeo4j.Test.Resource.Comment
  alias AshNeo4j.Test.Struct
  require Ash.Query

  @datetime_usec_now DateTime.utc_now()
  @datetime_sec_now @datetime_usec_now |> DateTime.truncate(:second)
  @naive_datetime_sec_now @datetime_usec_now |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)
  @time_usec_now @datetime_usec_now |> DateTime.to_time()
  @time_sec_now @time_usec_now |> Time.truncate(:second)
  @today @datetime_usec_now |> DateTime.to_date()

  @type_properties %{
    #uuid: Ash.UUID.generate(),
    #array_atom: [:a, :b, :c],
    #array_integer: [1, 2, 3],
    #array_string: ["a", "b", "c"],
    #array_boolean: [true, true, false],
    #array_map: [%{a: "a"}, %{b: "b"}],
    atom: :a,
    binary: <<104, 101, 197, 130, 197, 130, 111>>,
    boolean: true,
    #ci_string: "hello",
    date: @today,
    datetime: @datetime_sec_now,
    decimal: Decimal.new("4.2"),
    float: 1.23456789,
    function: &Neo4jHelper.create_node/2,
    integer: 1,
    json_string: "{\"a\": \"a\", \"b\": 1, \"c\": false}",
    keyword: [a: :atom, s: "string"],
    map: %{a: "a", b: 1, c: false},
    mapset: MapSet.new([1, :two, false]),
    module: AshNeo4j.DataLayer,
    naive_datetime: @naive_datetime_sec_now,
    regex: ~r/foo/iu,
    string: "Hello",
    struct: %Struct{},
    term: %Struct{},
    time: @time_sec_now,
    time_usec: @time_usec_now, # needs ash with #2023 PR
    tuple: {:a, 1, false},
    utc_datetime_usec: @datetime_usec_now,
    url_encoded_binary: "https://www.diffo.dev/"
  }

  @base64_url_encoded_binary "aHR0cHM6Ly93d3cuZGlmZm8uZGV2Lw"
  @type_node_properties Map.put(@type_properties, :url_encoded_binary, @base64_url_encoded_binary)

  setup_all do
    {result, _} = Boltx.start_link(Application.get_env(:boltx, Bolt))
    result
  end

  setup do
    on_exit(fn ->
      #Neo4jHelper.delete_notes(:Type)
      #Neo4jHelper.delete_nodes(:Post)
      #Neo4jHelper.delete_nodes(:Comment)
      Neo4jHelper.delete_all()
    end)
  end

  describe "doctests" do
    doctest AshNeo4j.Cypher
    doctest Neo4jHelper
  end

  describe "Boltx configuration tests" do
      test "neo4j is running" do
        assert Boltx.query!(Bolt, "return 1 as n") |> Boltx.Response.first() == %{"n" => 1}
      end
  end

  describe "Neo4jHelper tests" do
    test "type node without properties can be created using Neo4jHelper" do
      assert {:ok, %{records: records}} = Neo4jHelper.create_node(:Type, %{})
      assert length(records) == 1
      node = records |> List.first() |> List.first()
      assert node.labels == ["Type"]
    end

    test "type node without properties can be read using Neo4jHelper" do
      Neo4jHelper.create_node(:Type, %{})
      assert {:ok, %{records: records}} = Neo4jHelper.read_nodes(:Type, %{})
      assert length(records) == 1
      node = records |> List.first() |> List.first()
      assert node.labels == ["Type"]
    end

    test "type node with properties can be created using Neo4jHelper" do
      assert {:ok, %{records: records}} =  Neo4jHelper.create_node(:Type, @type_properties)
      assert length(records) == 1
      node = records |> List.first() |> List.first()
      assert node.labels == ["Type"]
    end

    test "type node with properties can be read using Neo4jHelper" do
      Neo4jHelper.create_node(:Type, @type_properties)
      assert {:ok, %{records: records}} = Neo4jHelper.read_nodes(:Type, %{string: "Hello"})
      assert length(records) == 1
      node = records |> List.first() |> List.first()
      assert node.labels == ["Type"]
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
  end

  describe "Ash read action tests" do
    test "type node can be read using ash" do
      Neo4jHelper.create_node(:Type, @type_properties) #|> IO.inspect(label: "create_node response")
      type = Ash.read_one!(Type) #|> IO.inspect(label: "ash read_one response")
      Enum.each(@type_properties, fn {key, value} -> assert Map.get(type, key) == value end)
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

    test "post comment relationship can be read using ash - post with single comment" do
      create_posts_with_comments(1, 1)

      # read Post using Ash, loading related comments
      result = Post |> Ash.Query.for_read(:read) |> Ash.Query.load([:comments]) |> Ash.Query.filter_input([title: [eq: "post1"]]) |> Ash.read_one!()
      #|> IO.inspect(label: "ash read post1 loading comments")
      assert length(result.comments) == 1
    end

    test "post comment relationship can be read using ash - post with two comments" do
      create_posts_with_comments(1, 2)

      # read Post using Ash, loading related comments
      result = Post |> Ash.Query.for_read(:read) |> Ash.Query.load([:comments]) |> Ash.Query.filter_input([title: [eq: "post1"]]) |> Ash.read!()
      #|> IO.inspect(label: "ash read post1 loading comments")
      [post | _ ] = result
      assert length(post.comments) == 2
    end

    test "comment post relationship can be read using ash" do
      create_posts_with_comments(1, 2)

      # read Comments using Ash, loading related Post
      result = Comment |> Ash.Query.for_read(:read) |> Ash.Query.load([:post]) |> Ash.Query.filter_input([title: [eq: "comment1.1"]]) |> Ash.read_one!()
      #|> IO.inspect(label: "ash read comment1.1 loading post")
      assert result.title == "comment1.1"
      assert result.post.title == "post1"
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
  end

  describe "ash create action tests" do
    test "type node can be created using ash without properties" do
      {:ok, type} = Type |> Ash.Changeset.for_create(:create, %{}) |> Ash.create()
      refute type.uuid == nil
      assert type.atom == :a
      Enum.each(Map.drop(@type_properties, [:uuid, :atom]), fn {key, _value} -> assert Map.get(type, key) == nil end)
    end

    test "type node can be created using ash with properties" do
      {:ok, type} = Type |> Ash.Changeset.for_create(:create, @type_properties) |> Ash.create() |> IO.inspect(label: "ash create response")
      Enum.each(@type_properties, fn {key, value} ->  assert Map.get(type, key) == value end)
    end

    test "post node can be created using ash" do
    {:ok, post} = Post |> Ash.Changeset.for_create(:create, %{title: "post4"}) |> Ash.create()
    assert post.title == "post4"
    end

    test "comment node can be created using ash" do
      {:ok, comment} = Comment |> Ash.Changeset.for_create(:create, %{title: "comment4"}) |> Ash.create()
      assert comment.title == "comment4"
    end

    defp create_post_nodes(count) when is_integer(count) do
      for i <- 1..count do
        Neo4jHelper.create_node(:Post, %{title: "post#{i}", score: i, public: true, uuid: Ash.UUID.generate()})
      end
    end

    defp create_comment_nodes(count) when is_integer(count) do
      for i <- 1..count do
        Neo4jHelper.create_node(:Comment, %{title: "comment#{i}", uuid: Ash.UUID.generate()})
      end
    end

    defp create_posts_with_comments(posts, comments) when is_integer(posts) and is_integer(comments) do
      for post <- 1..posts do
        Neo4jHelper.create_node(:Post, %{title: "post#{post}", uuid: post_uuid = Ash.UUID.generate()})
        for comment <- 1..comments do
          Neo4jHelper.create_node(:Comment, %{title: "comment#{post}.#{comment}", uuid: comment_uuid = Ash.UUID.generate()})
          Neo4jHelper.relate_nodes(:Comment, %{uuid: comment_uuid}, :Post, %{uuid: post_uuid}, :BELONGS_TO, :outgoing)
        end
      end
    end
  end
end
