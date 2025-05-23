defmodule AshNeo4j.Test do
  use ExUnit.Case, async: false
  alias AshNeo4j.Neo4jHelper
  alias AshNeo4j.Test.Resource.Type
  alias AshNeo4j.Test.Resource.Post
  alias AshNeo4j.Test.Resource.Comment
  alias AshNeo4j.Test.Resource.Service
  alias AshNeo4j.Test.Resource.Resource
  alias AshNeo4j.Test.Struct
  require Ash.Query

  @type_properties %{
    array_atom: [:a, :b, :c],
    array_integer: [1, 2, 3],
    array_string: ["a", "b", "c"],
    array_boolean: [true, true, false],
    array_map: [%{a: "a"}, %{b: "b"}],
    array_struct: [%Struct{}],
    # note neo4j arrays must all be same neo4j type (in this case all strings)
    array_term: [:a, "a", %Struct{}],
    atom: :a,
    binary: <<1, 2, 3>>,
    # binary: <<104, 101, 197, 130, 197, 130, 111>>,
    boolean: true,
    ci_string: "HELLO",
    date: ~D[2025-05-11],
    datetime: ~U[2025-05-11 07:45:41Z],
    decimal: Decimal.new("4.2"),
    duration: %Duration{year: 1, month: 2, week: 3, day: 4, hour: 5, minute: 6, second: 7, microsecond: {8, 6}},
    float: 1.23456789,
    function: &Neo4jHelper.create_node/2,
    integer: 1,
    json_string: "{\"a\": \"a\", \"b\": 1, \"c\": false}",
    keyword: [a: :atom, s: "string"],
    map: %{a: "a", b: 1, c: false, d: nil},
    mapset: MapSet.new([1, :two, false]),
    module: AshNeo4j.DataLayer,
    naive_datetime: ~N[2025-05-11 07:45:41],
    regex: ~r/foo/iu,
    string: "Hello",
    struct: %Struct{},
    term: %Struct{},
    time: ~T[07:45:41Z],
    time_usec: ~T[07:45:41.429903Z],
    tuple: {:a, 1, false},
    utc_datetime_usec: ~U[2025-05-11 07:45:41.429903Z],
    url: "aHR0cHM6Ly93d3cuZGlmZm8uZGV2Lw"
  }

  @type_node_properties %{
    "array_atom" => [":a", ":b", ":c"],
    "array_integer" => [1, 2, 3],
    "array_string" => ["a", "b", "c"],
    "array_boolean" => [true, true, false],
    "array_map" => ["%{a: \"a\"}", "%{b: \"b\"}"],
    "array_struct" => [
      "%AshNeo4j.Test.Struct{a: :a, b: false, d: Decimal.new(\"4.2\"), f: 1.2, i: 0, n: nil, s: \"Hello\"}"
    ],
    # note neo4j arrays must all be same neo4j type (in this case all strings)
    "array_term" => [
      ":a",
      "a",
      "%AshNeo4j.Test.Struct{a: :a, b: false, d: Decimal.new(\"4.2\"), f: 1.2, i: 0, n: nil, s: \"Hello\"}"
    ],
    "atom" => ":a",
    "binary" => "\x01\x02\x03",
    "boolean" => true,
    "ci_string" => "HELLO",
    "date" => "2025-05-11",
    "datetime" => "2025-05-11T07:45:41Z",
    "decimal" => "Decimal.new(\"4.2\")",
    "duration" => %Boltx.Types.Duration{
      seconds: 7,
      nanoseconds: 8000,
      minutes: 6,
      hours: 5,
      days: 25,
      months: 2,
      weeks: 0,
      years: 1
    },
    "float" => 1.23456789,
    "function" => "&AshNeo4j.Neo4jHelper.create_node/2",
    "integer" => 1,
    "json_string" => "{\"a\": \"a\", \"b\": 1, \"c\": false}",
    "keyword" => ["{:a, :atom}", "{:s, string}"],
    # serialisation order indeterminate
    "map" => "%{a: \"a\", b: 1, c: false, d: nil}",
    # serialisation order indeterminate
    "mapset" => "MapSet.new([1, :two, false])",
    "module" => ":Elixir.AshNeo4j.DataLayer",
    "naive_datetime" => "2025-05-11T07:45:41",
    "regex" => "~r/foo/iu",
    "string" => "Hello",
    "struct" => "%AshNeo4j.Test.Struct{a: :a, b: false, d: Decimal.new(\"4.2\"), f: 1.2, i: 0, n: nil, s: \"Hello\"}",
    "term" => "%AshNeo4j.Test.Struct{a: :a, b: false, d: Decimal.new(\"4.2\"), f: 1.2, i: 0, n: nil, s: \"Hello\"}",
    "time" => "07:45:41",
    "time_usec" => "07:45:41.429903",
    "tuple" => "{:a, 1, false}",
    "utc_datetime_usec" => "2025-05-11T07:45:41.429903Z",
    "url" => "aHR0cHM6Ly93d3cuZGlmZm8uZGV2Lw"
  }

  @url "https://www.diffo.dev/"

  setup_all do
    {result, _} = Boltx.start_link(Application.get_env(:boltx, Bolt))
    result
  end

  setup do
    on_exit(fn ->
      # Neo4jHelper.delete_nodes(:Actor)
      # Neo4jHelper.delete_nodes(:Movie)
      # Neo4jHelper.delete_nodes(:Type)
      # Neo4jHelper.delete_nodes(:Post)
      # Neo4jHelper.delete_nodes(:Comment)
      Neo4jHelper.delete_all()
    end)
  end

  describe "doctests" do
    doctest AshNeo4j.DataLayer.BoltxHelper
    doctest AshNeo4j.Cypher
    doctest AshNeo4j.Neo4jHelper
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
      Enum.each(@type_node_properties, fn {key, _value} -> assert Map.get(node.properties, "#{key}") == nil end)
    end

    test "type node with properties can be created using Neo4jHelper" do
      assert {:ok, %{records: records}} = Neo4jHelper.create_node(:Type, @type_properties)
      assert length(records) == 1
      node = records |> List.first() |> List.first()
      assert node.labels == ["Type"]
      # map and mapset have indeterminate order so we don't check them exactly
      refute Map.get(node.properties, "map") == nil
      refute Map.get(node.properties, "mapset") == nil

      Enum.each(Map.drop(@type_node_properties, ["map", "mapset"]), fn {key, value} ->
        assert Map.get(node.properties, "#{key}") == value
      end)
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
      # |> IO.inspect(label: "create_node response")
      Neo4jHelper.create_node(:Type, @type_properties)
      # |> IO.inspect(label: "ash read_one response")
      type = Ash.read_one!(Type)
      Enum.each(@type_properties, fn {key, value} -> assert Map.get(type, key) == value end)
    end

    test "post node can be read using ash" do
      create_post_nodes(2)
      # read using Ash
      resources = Ash.read!(Post)
      assert length(resources) == 2
      # read using Ash with filter
      result = Post |> Ash.Query.for_read(:read) |> Ash.Query.filter_input(title: [eq: "post2"]) |> Ash.read!()
      # |> IO.inspect(label: :post_node)
      assert length(result) == 1
      assert result |> Enum.at(0) |> Map.get(:title) == "post2"
    end

    test "comment node can be read using ash" do
      create_comment_nodes(2)
      # read using Ash
      resources = Ash.read!(Comment)
      assert length(resources) == 2
      # read using Ash with filter
      result = Comment |> Ash.Query.for_read(:read) |> Ash.Query.filter_input(title: [eq: "comment2"]) |> Ash.read!()
      # |> IO.inspect(label: :comment_node)
      assert length(result) == 1
      assert result |> Enum.at(0) |> Map.get(:title) == "comment2"
    end

    test "post comment relationship can be read using ash - post with single comment" do
      create_posts_with_comments(1, 1)

      # read Post using Ash, loading related comments
      result =
        Post
        |> Ash.Query.for_read(:read)
        |> Ash.Query.load([:comments])
        |> Ash.Query.filter_input(title: [eq: "post1"])
        |> Ash.read_one!()

      # |> IO.inspect(label: "ash read post1 loading comments")
      assert length(result.comments) == 1
    end

    test "post comment relationship can be read using ash - post with two comments" do
      create_posts_with_comments(1, 2)

      # read Post using Ash, loading related comments
      result =
        Post
        |> Ash.Query.for_read(:read)
        |> Ash.Query.load([:comments])
        |> Ash.Query.filter_input(title: [eq: "post1"])
        |> Ash.read!()

      # |> IO.inspect(label: "ash read post1 loading comments")
      [post | _] = result
      assert length(post.comments) == 2
    end

    test "comment post relationship can be read using ash" do
      create_posts_with_comments(1, 2)

      # read Comments using Ash, loading related Post
      result =
        Comment
        |> Ash.Query.for_read(:read)
        |> Ash.Query.load([:post])
        |> Ash.Query.filter_input(title: [eq: "comment1.1"])
        |> Ash.read_one!()

      # |> IO.inspect(label: "ash read comment1.1 loading post")
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
      create_post_nodes(3)

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
      {:ok, type} = Type |> Ash.Changeset.for_create(:create, @type_properties) |> Ash.create()
      # |> IO.inspect(label: "ash create response")
      assert type.url == @url
      Enum.each(Map.drop(@type_properties, [:url]), fn {key, value} -> assert Map.get(type, key) == value end)
    end

    test "post node can be created using ash" do
      {:ok, post} = Post |> Ash.Changeset.for_create(:create, %{title: "post4"}) |> Ash.create()
      assert post.title == "post4"
    end

    test "comment node can be created using ash" do
      {:ok, comment} = Comment |> Ash.Changeset.for_create(:create, %{title: "comment4"}) |> Ash.create()
      assert comment.title == "comment4"
    end
  end

  describe "ash update action tests" do
    test "post can be updated using ash" do
      {:ok, post} = Post |> Ash.Changeset.for_create(:create, %{title: "post5"}) |> Ash.create()

      {:ok, updated_post} =
        post |> Ash.Changeset.for_update(:update, %{score: 1}) |> Ash.update() |> Ash.load([:comments])

      assert updated_post.score == 1
    end

    test "post and comment node can be related using ash" do
      {:ok, post} = Post |> Ash.Changeset.for_create(:create, %{title: "post6"}) |> Ash.create()
      {:ok, comment} = Comment |> Ash.Changeset.for_create(:create, %{title: "comment5"}) |> Ash.create()
      {:ok, related_post} = post |> Ash.Changeset.for_update(:update, add_comments: [comment.id]) |> Ash.update()
      # the post should have the comment
      assert hd(related_post.comments).title == "comment5"
      # now read the comment, it should have the post_id
      related_comment = comment |> Ash.load!([:post_id])
      assert related_comment.post_id == post.id
    end

    test "post and comments nodes can be related using ash" do
      {:ok, post} = Post |> Ash.Changeset.for_create(:create, %{title: "post7"}) |> Ash.create()
      {:ok, comment1} = Comment |> Ash.Changeset.for_create(:create, %{title: "comment6"}) |> Ash.create()
      {:ok, comment2} = Comment |> Ash.Changeset.for_create(:create, %{title: "comment7"}) |> Ash.create()

      {:ok, related_post} =
        post |> Ash.Changeset.for_update(:update, add_comments: [comment1.id, comment2.id]) |> Ash.update()

      # the post should have the comments
      assert length(related_post.comments) == 2
      # now read the comments, they should have the post_id
      related_comment1 = comment1 |> Ash.load!([:post_id])
      related_comment2 = comment2 |> Ash.load!([:post_id])
      assert related_comment1.post_id == post.id
      assert related_comment2.post_id == post.id
    end

    test "post and comment nodes can be updated and related using ash" do
      {:ok, post} = Post |> Ash.Changeset.for_create(:create, %{title: "post7"}) |> Ash.create()
      {:ok, comment1} = Comment |> Ash.Changeset.for_create(:create, %{title: "comment6"}) |> Ash.create()
      {:ok, comment2} = Comment |> Ash.Changeset.for_create(:create, %{title: "comment7"}) |> Ash.create()

      {:ok, related_post} =
        post |> Ash.Changeset.new |> Ash.Changeset.change_attribute(:score, 1) |> Ash.Changeset.for_update(:update, add_comments: [comment1.id, comment2.id])
        |> Ash.update()
      # the post should have the comments
      assert length(related_post.comments) == 2
      # the post should also have the updated score
      assert related_post.score == 1
    end

    test "service-service-resource-resource relationships using ash" do
      {:ok, parent_service} = Service |> Ash.Changeset.for_create(:create, %{name: "parent_service"}) |> Ash.create()
      {:ok, child_service} = Service |> Ash.Changeset.for_create(:create, %{name: "child_service"}) |> Ash.create()

      {:ok, _related_parent_service} =
        parent_service |> Ash.Changeset.for_update(:update, manage_services: [child_service.id]) |> Ash.update()

      {:ok, parent_resource} = Resource |> Ash.Changeset.for_create(:create, %{name: "parent_resource"}) |> Ash.create()

      {:ok, _related_child_service} =
        child_service |> Ash.Changeset.for_update(:update, use_resources: [parent_resource.id]) |> Ash.update()

      {:ok, child_resource} = Resource |> Ash.Changeset.for_create(:create, %{name: "child_resource"}) |> Ash.create()

      {:ok, _related_parent_resource} =
        parent_resource |> Ash.Changeset.for_update(:update, use_resources: [child_resource.id]) |> Ash.update()

      assert Neo4jHelper.nodes_relate_how?(
               :Service,
               %{name: "parent_service"},
               :Service,
               %{name: "child_service"},
               :MANAGES,
               :outgoing
             )

      assert Neo4jHelper.nodes_relate_how?(
               :Service,
               %{name: "child_service"},
               :Resource,
               %{name: "parent_resource"},
               :USES,
               :outgoing
             )

      assert Neo4jHelper.nodes_relate_how?(
               :Resource,
               %{name: "parent_resource"},
               :Resource,
               %{name: "child_resource"},
               :USES,
               :outgoing
             )
    end
  end

  describe "ash destroy action tests" do
    test "type can be destroyed using ash" do
      {:ok, type} = Type |> Ash.Changeset.for_create(:create, %{}) |> Ash.create()
      :ok = type |> Ash.destroy!()
    end

    test "related post can be destroyed using ash" do
      {:ok, post} = Post |> Ash.Changeset.for_create(:create, %{title: "post8"}) |> Ash.create()
      {:ok, comment} = Comment |> Ash.Changeset.for_create(:create, %{title: "comment8"}) |> Ash.create()

      {:ok, related_post} =
        post |> Ash.Changeset.for_update(:update, add_comments: [comment.id]) |> Ash.update()

      :ok = related_post |> Ash.destroy()

      {:ok, preserved_comment} = comment |> Ash.load([:post_id])
      assert Map.get(preserved_comment, :post_id) == nil
    end

    test "related comment can be destroyed using ash" do
      {:ok, post} = Post |> Ash.Changeset.for_create(:create, %{title: "post9"}) |> Ash.create()
      {:ok, comment} = Comment |> Ash.Changeset.for_create(:create, %{title: "comment9"}) |> Ash.create()

      {:ok, related_post} = post |> Ash.Changeset.for_update(:update, add_comments: [comment.id]) |> Ash.update()

      :ok = comment |> Ash.destroy()

      {:ok, preserved_post} = related_post |> Ash.load([:comments])
      assert preserved_post.comments == []
    end
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
        Neo4jHelper.create_node(:Comment, %{
          title: "comment#{post}.#{comment}",
          uuid: comment_uuid = Ash.UUID.generate()
        })

        Neo4jHelper.relate_nodes(:Comment, %{uuid: comment_uuid}, :Post, %{uuid: post_uuid}, :BELONGS_TO, :outgoing)
      end
    end
  end
end
