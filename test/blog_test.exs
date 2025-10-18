# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Blog.Test do
  @moduledoc false
  use ExUnit.Case, async: false
  alias AshNeo4j.Neo4jHelper
  alias AshNeo4j.BoltxHelper
  alias AshNeo4j.Test.Resource.Author
  alias AshNeo4j.Test.Resource.Post
  alias AshNeo4j.Test.Resource.Comment
  alias AshNeo4j.Test.Resource.Tag
  require Ash.Query
  import AshNeo4j.Test.Util, only: [check_enrichment: 5]

  setup_all do
    BoltxHelper.start()
  end

  setup do
    on_exit(fn ->
      Neo4jHelper.delete_nodes(:Author)
      Neo4jHelper.delete_nodes(:Post)
      Neo4jHelper.delete_nodes(:Comment)
      Neo4jHelper.delete_nodes(:Tag)
    end)
  end

  describe "Boltx configuration tests" do
    test "neo4j is running" do
      assert BoltxHelper.is_connected()
    end
  end

  describe "Neo4jHelper tests" do
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
    test "post node can be read using ash" do
      create_post_nodes(2)
      # read using Ash
      resources = Ash.read!(Post)
      assert length(resources) == 2
      # read using Ash with filter
      result = Post |> Ash.Query.for_read(:read) |> Ash.Query.filter_input(title: [eq: "post2"]) |> Ash.read!()
      assert length(result) == 1
      post = hd(result)
      assert is_struct(post, Post)
      assert post.title == "post2"
      assert is_list(post.comments)
    end

    test "comment node can be read using ash" do
      create_comment_nodes(2)
      # read using Ash
      resources = Ash.read!(Comment)
      assert length(resources) == 2
      # read using Ash with filter
      result = Comment |> Ash.Query.for_read(:read) |> Ash.Query.filter_input(title: [eq: "comment2"]) |> Ash.read!()
      assert length(result) == 1
      comment = hd(result)
      check_enrichment(comment, :post, nil, :post_id, nil)
    end

    test "post comment relationship can be read using ash - post with single comment" do
      create_posts_with_comments(1, 1)

      # read Post using Ash, loading related comments
      post =
        Post
        |> Ash.Query.for_read(:read)
        |> Ash.Query.filter_input(title: [eq: "post1"])
        |> Ash.Query.load([:comments])
        |> Ash.read_one!()

      assert is_struct(post, Post)
      assert length(post.comments) == 1
      assert is_struct(hd(post.comments), Comment)
    end

    test "post comment relationship can be read using ash - post with two comments" do
      create_posts_with_comments(1, 2)

      # read Post using Ash, loading related comments
      post =
        Post
        |> Ash.Query.for_read(:read)
        |> Ash.Query.load([:comments])
        |> Ash.Query.filter_input(title: [eq: "post1"])
        |> Ash.read_one!()

      assert is_struct(post, Post)
      assert length(post.comments) == 2
      Enum.each(post.comments, &assert(is_struct(&1, Comment)))
    end

    test "comment post relationship can be read using ash" do
      create_posts_with_comments(1, 2)

      # read Comments using Ash, loading related Post
      comment =
        Comment
        |> Ash.Query.for_read(:read)
        |> Ash.Query.load([:post])
        |> Ash.Query.filter_input(title: [eq: "comment1.1"])
        |> Ash.read_one!()

      assert is_struct(comment, Comment)
      assert comment.title == "comment1.1"
      assert is_struct(comment.post, Post)
      assert comment.post.title == "post1"
    end

    test "posts have sorted comments" do
      create_posts_with_comments(1, 3)

      results =
        Post |> Ash.Query.for_read(:read) |> Ash.read!()

      assert length(results) == 1
      post = hd(results)
      assert length(post.comments) == 3
      titles = Enum.into(post.comments, [], &Map.get(&1, :title))
      # were the titles sorted?
      assert Enum.sort(titles) == titles
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

    test "optimised is_nil predicate can be applied" do
      create_post_nodes(3)

      results =
        Post
        |> Ash.Query.for_read(:read)
        |> Ash.Query.filter(is_nil(unique))
        |> Ash.read!()

      assert length(results) == 3

      results =
        Post
        |> Ash.Query.for_read(:read)
        |> Ash.Query.filter(is_nil(score))
        |> Ash.read!()

      assert length(results) == 0
    end

    test "multiple predicates can be applied - and" do
      create_post_nodes(3)

      results =
        Post
        |> Ash.Query.for_read(:read)
        |> Ash.Query.filter(score >= 1 and score <= 2)
        |> Ash.read!()

      assert length(results) == 2
    end

    test "multiple predicates can be applied - or" do
      create_post_nodes(3)

      results =
        Post
        |> Ash.Query.for_read(:read)
        |> Ash.Query.filter(score < 1 or score > 2)
        |> Ash.read!()

      assert length(results) == 1
    end
  end

  describe "ash create action tests" do
    test "author node can be created using ash" do
      {:ok, author} = Author |> Ash.Changeset.for_create(:create, %{name: "author"}) |> Ash.create()
      assert author.name == "author"
    end

    test "post node can be created using ash - failed must have an author" do
      {:error, _error} = Post |> Ash.Changeset.for_create(:create, %{title: "post4"}) |> Ash.create()
    end

    test "post node can be created using ash" do
      {:ok, author} = Author |> Ash.Changeset.for_create(:create, %{name: "author"}) |> Ash.create()
      {:ok, post} = Post |> Ash.Changeset.for_create(:create, %{title: "post4", written_by: author.id}) |> Ash.create()
      assert post.title == "post4"
      assert post.author_id == author.id
      assert is_struct(post.author, Author)
    end

    test "comment node can be created using ash" do
      {:ok, comment} = Comment |> Ash.Changeset.for_create(:create, %{title: "comment4"}) |> Ash.create()
      assert comment.title == "comment4"
    end
  end

  describe "ash update action tests" do
    test "post can be updated using ash" do
      {:ok, author} = Author |> Ash.Changeset.for_create(:create, %{name: "author"}) |> Ash.create()
      {:ok, post} = Post |> Ash.Changeset.for_create(:create, %{title: "post5", written_by: author.id}) |> Ash.create()

      {:ok, updated_post} =
        post |> Ash.Changeset.for_update(:update, %{score: 1}) |> Ash.update()

      assert updated_post.score == 1
    end

    test "post attributes can be updated to nil using ash" do
      {:ok, author} = Author |> Ash.Changeset.for_create(:create, %{name: "author"}) |> Ash.create()

      {:ok, post} =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "post5", score: 1, written_by: author.id})
        |> Ash.create()

      {:ok, updated_post} =
        post |> Ash.Changeset.for_update(:update, %{score: nil}) |> Ash.update()

      assert updated_post.score == nil
    end

    test "post and comment node can be related using ash" do
      {:ok, author} = Author |> Ash.Changeset.for_create(:create, %{name: "author"}) |> Ash.create()
      {:ok, post} = Post |> Ash.Changeset.for_create(:create, %{title: "post6", written_by: author.id}) |> Ash.create()
      {:ok, comment} = Comment |> Ash.Changeset.for_create(:create, %{title: "comment5"}) |> Ash.create()
      {:ok, related_post} = post |> Ash.Changeset.for_update(:update, add_comments: [comment.id]) |> Ash.update()
      # the post should have the comment
      assert hd(related_post.comments).title == "comment5"
      # now read the comment, it should have the post_id
      related_comment = comment |> Ash.load!([:post_id])
      assert related_comment.post_id == post.id
    end

    test "post and comments nodes can be related using ash update" do
      {:ok, author} = Author |> Ash.Changeset.for_create(:create, %{name: "author"}) |> Ash.create()
      {:ok, post} = Post |> Ash.Changeset.for_create(:create, %{title: "post7", written_by: author.id}) |> Ash.create()
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

    test "post and comment nodes can be updated and related using ash update" do
      {:ok, author} = Author |> Ash.Changeset.for_create(:create, %{name: "author"}) |> Ash.create()
      {:ok, post} = Post |> Ash.Changeset.for_create(:create, %{title: "post7", written_by: author.id}) |> Ash.create()
      {:ok, comment1} = Comment |> Ash.Changeset.for_create(:create, %{title: "comment6"}) |> Ash.create()
      {:ok, comment2} = Comment |> Ash.Changeset.for_create(:create, %{title: "comment7"}) |> Ash.create()

      {:ok, related_post} =
        post
        |> Ash.Changeset.new()
        |> Ash.Changeset.change_attribute(:score, 1)
        |> Ash.Changeset.for_update(:update, add_comments: [comment1.id, comment2.id])
        |> Ash.update()

      # the post should have the comments
      assert length(related_post.comments) == 2
      # the post should also have the updated score
      assert related_post.score == 1

      assert Neo4jHelper.nodes_relate_how?(
               :Post,
               %{title: "post7"},
               :Comment,
               %{title: "comment6"},
               :BELONGS_TO,
               :incoming
             )

      assert Neo4jHelper.nodes_relate_how?(
               :Post,
               %{title: "post7"},
               :Comment,
               %{title: "comment7"},
               :BELONGS_TO,
               :incoming
             )
    end

    test "post and comment nodes can be related and unrelated using ash update" do
      {:ok, author} = Author |> Ash.Changeset.for_create(:create, %{name: "author"}) |> Ash.create()
      {:ok, post} = Post |> Ash.Changeset.for_create(:create, %{title: "post7", written_by: author.id}) |> Ash.create()
      {:ok, comment1} = Comment |> Ash.Changeset.for_create(:create, %{title: "comment8"}) |> Ash.create()
      {:ok, comment2} = Comment |> Ash.Changeset.for_create(:create, %{title: "comment9"}) |> Ash.create()

      {:ok, related_post} =
        post
        |> Ash.Changeset.new()
        |> Ash.Changeset.for_update(:update, add_comments: [comment1.id, comment2.id])
        |> Ash.update()

      refreshed_comment1 = comment1 |> Ash.reload!()
      refreshed_comment2 = comment2 |> Ash.reload!()
      check_enrichment(refreshed_comment1, :post, Ash.NotLoaded, :post_id, post.id)
      check_enrichment(refreshed_comment2, :post, Ash.NotLoaded, :post_id, post.id)

      {:ok, unrelated_post} =
        related_post
        |> Ash.Changeset.new()
        |> Ash.Changeset.for_update(:unrelate, remove_comments: [comment2.id])
        |> Ash.update()

      # the unrelated post should have only the first comment
      assert length(unrelated_post.comments) == 1

      refreshed_comment2 = comment2 |> Ash.reload!()

      assert Neo4jHelper.nodes_relate_how?(
               :Post,
               %{title: "post7"},
               :Comment,
               %{title: "comment8"},
               :BELONGS_TO,
               :incoming
             )

      refute Neo4jHelper.nodes_relate_how?(
               :Post,
               %{title: "post7"},
               :Comment,
               %{title: "comment9"},
               :BELONGS_TO,
               :incoming
             )

      check_enrichment(refreshed_comment2, :post, nil, :post_id, nil)
    end
  end

  describe "ash destroy action tests" do
    test "unrelated author can be destroyed using ash" do
      {:ok, author} = Author |> Ash.Changeset.for_create(:create, %{name: "author"}) |> Ash.create()
      :ok = author |> Ash.destroy()
    end

    test "author cannot be destroyed while related to post using ash" do
      {:ok, author} = Author |> Ash.Changeset.for_create(:create, %{name: "author"}) |> Ash.create()
      {:ok, post} = Post |> Ash.Changeset.for_create(:create, %{title: "post8", written_by: author.id}) |> Ash.create()
      {:error, _error} = author |> Ash.destroy()

      # now unrelate by deleting the post
      :ok = post |> Ash.destroy()

      :ok = author |> Ash.destroy()
    end

    test "related post can be destroyed using ash" do
      {:ok, author} = Author |> Ash.Changeset.for_create(:create, %{name: "author"}) |> Ash.create()
      {:ok, post} = Post |> Ash.Changeset.for_create(:create, %{title: "post8", written_by: author.id}) |> Ash.create()
      {:ok, comment} = Comment |> Ash.Changeset.for_create(:create, %{title: "comment8"}) |> Ash.create()

      {:ok, related_post} =
        post |> Ash.Changeset.for_update(:update, add_comments: [comment.id]) |> Ash.update()

      :ok = related_post |> Ash.destroy()

      {:ok, preserved_comment} = comment |> Ash.load([:post_id])
      assert Map.get(preserved_comment, :post_id) == nil
    end

    test "related comment can be destroyed using ash" do
      {:ok, author} = Author |> Ash.Changeset.for_create(:create, %{name: "author"}) |> Ash.create()
      {:ok, post} = Post |> Ash.Changeset.for_create(:create, %{title: "post9", written_by: author.id}) |> Ash.create()
      {:ok, comment} = Comment |> Ash.Changeset.for_create(:create, %{title: "comment9"}) |> Ash.create()

      {:ok, related_post} = post |> Ash.Changeset.for_update(:update, add_comments: [comment.id]) |> Ash.update()

      :ok = comment |> Ash.destroy()

      {:ok, preserved_post} = related_post |> Ash.load([:comments])
      assert preserved_post.comments == []
    end
  end

  describe "sort, offset and limit tests" do
    test "sort is optimised" do
      for i <- 16..18 do
        Comment |> Ash.Changeset.for_create(:create, %{title: "comment#{i}"}) |> Ash.create()
      end

      {:ok, result} = Comment |> Ash.Query.sort(title: :desc) |> Ash.read()
      assert length(result) == 3
      expected = ["comment18", "comment17", "comment16"]
      assert Enum.into(result, [], fn comment -> comment.title end) == expected
    end

    test "sort asc and desc is optimised" do
      {:ok, author} = Author |> Ash.Changeset.for_create(:create, %{name: "author"}) |> Ash.create()

      for i <- 1..3 do
        Post
        |> Ash.Changeset.for_create(:create, %{title: "post#{i}", score: div(i + 1, 2), written_by: author.id})
        |> Ash.create()
      end

      {:ok, result} = Post |> Ash.Query.sort(score: :desc, title: :asc) |> Ash.read()
      expected_title = ["post3", "post1", "post2"]
      expected_score = [2, 1, 1]
      assert Enum.into(result, [], fn post -> post.title end) == expected_title
      assert Enum.into(result, [], fn post -> post.score end) == expected_score
    end

    test "limit is optimised" do
      for i <- 11..15 do
        Comment |> Ash.Changeset.for_create(:create, %{title: "comment#{i}"}) |> Ash.create()
      end

      {:ok, result} = Comment |> Ash.Query.limit(3) |> Ash.read()
      assert length(result) == 3
    end

    test "sort and limit together" do
      for i <- 16..19 do
        Comment |> Ash.Changeset.for_create(:create, %{title: "comment#{i}"}) |> Ash.create()
      end

      {:ok, result} = Comment |> Ash.Query.sort(title: :desc) |> Ash.Query.limit(3) |> Ash.read()
      expected = ["comment19", "comment18", "comment17"]
      assert Enum.into(result, [], fn comment -> comment.title end) == expected
    end

    test "sort, offset and limit together" do
      for i <- 20..25 do
        Comment |> Ash.Changeset.for_create(:create, %{title: "comment#{i}"}) |> Ash.create()
      end

      {:ok, result} = Comment |> Ash.Query.sort(title: :asc) |> Ash.Query.offset(2) |> Ash.Query.limit(2) |> Ash.read()
      expected = ["comment22", "comment23"]
      assert Enum.into(result, [], fn comment -> comment.title end) == expected
    end
  end

  describe "many-to-many relationship tests" do
    # fails with Ash.Error.Unknown "couldn't relate notes, despite attributes containing post_id"
    @tag bugged: true
    test "many posts can be tagged with each tag" do
      {:ok, author} = Author |> Ash.Changeset.for_create(:create, %{name: "author"}) |> Ash.create()
      {:ok, post1} = Post |> Ash.create(%{title: "post1", written_by: author.id})
      {:ok, post2} = Post |> Ash.create(%{title: "post2", written_by: author.id})
      {:ok, tag1} = Tag |> Ash.create(%{value: "tag1"})
      {:ok, tag2} = Tag |> Ash.create(%{value: "tag2"})
      posts = [post1, post2]
      tag_ids = [tag1.id, tag2.id]

      # tag posts
      Enum.into(posts, [], fn post ->
        {:ok, post} =
          post
          |> Ash.Changeset.new()
          |> Ash.Changeset.for_update(:manage_tags, tags: tag_ids)
          |> Ash.update()

        post
      end)

      # check relationships in neo4j
      for post <- posts, tag_id <- tag_ids do
        assert Neo4jHelper.nodes_relate_how?(
                 :Post,
                 %{title: post.title},
                 :Tag,
                 %{uuid: tag_id},
                 :TAGS,
                 :incoming
               )
      end

      # retrieve posts and check they have tags
      for post <- posts do
        retrieved_post =
          Post
          |> Ash.Query.for_read(:read)
          |> Ash.Query.filter(id: post.id)
          |> Ash.read_one!()

        assert length(retrieved_post.tags) == length(tag_ids)
      end

      # retrieve tags and check they are related to posts
      for tag_id <- tag_ids do
        tag =
          Tag |> Ash.Query.for_read(:read) |> Ash.Query.filter(id: tag_id) |> Ash.read_one!()

        assert length(tag.posts) == length(posts)
      end
    end
  end

  defp create_post_nodes(count) when is_integer(count) do
    Neo4jHelper.create_node(:Author, %{name: "author1", uuid: author_uuid = Ash.UUID.generate()})

    for i <- 1..count do
      Neo4jHelper.create_node(:Post, %{title: "post#{i}", score: i, public: true, uuid: post_uuid = Ash.UUID.generate()})

      Neo4jHelper.relate_nodes(:Author, %{uuid: author_uuid}, :Post, %{uuid: post_uuid}, :WROTE, :outgoing)
    end
  end

  defp create_comment_nodes(count) when is_integer(count) do
    for i <- 1..count do
      Neo4jHelper.create_node(:Comment, %{title: "comment#{i}", uuid: Ash.UUID.generate()})
    end
  end

  defp create_posts_with_comments(posts, comments) when is_integer(posts) and is_integer(comments) do
    Neo4jHelper.create_node(:Author, %{name: "author1", uuid: author_uuid = Ash.UUID.generate()})

    for post <- 1..posts do
      Neo4jHelper.create_node(:Post, %{title: "post#{post}", uuid: post_uuid = Ash.UUID.generate()})
      Neo4jHelper.relate_nodes(:Author, %{uuid: author_uuid}, :Post, %{uuid: post_uuid}, :WROTE, :outgoing)

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
