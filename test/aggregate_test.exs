# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.AggregateTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Author
  alias AshNeo4j.Test.Resource.Post
  alias AshNeo4j.Test.Resource.Comment
  alias AshNeo4j.Test.Type.DogTypedStruct
  require Ash.Query

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  defp create_author do
    Author |> Ash.Changeset.for_create(:create, %{name: "Test Author"}) |> Ash.create!()
  end

  defp create_post(author, title) do
    Post
    |> Ash.Changeset.for_create(:create, %{title: title, written_by: author.id})
    |> Ash.create!()
  end

  defp create_comment(post, title) do
    Comment
    |> Ash.Changeset.for_create(:create, %{title: title, post_id: post.id})
    |> Ash.create!()
  end

  defp create_comment_with_dog(post, title, dog) do
    Comment
    |> Ash.Changeset.for_create(:create, %{title: title, post_id: post.id, dog: dog})
    |> Ash.create!()
  end

  describe "Ash.aggregate standalone" do
    test "count returns total related records across all matching resources" do
      author = create_author()
      post1 = create_post(author, "post1")
      post2 = create_post(author, "post2")
      create_comment(post1, "comment A")
      create_comment(post1, "comment B")
      create_comment(post2, "comment C")

      {:ok, %{total_comments: total}} = Ash.aggregate(Post, {:total_comments, :count, [path: [:comments]]})
      assert total == 3
    end

    test "count returns 0 when no related records exist" do
      create_author() |> create_post("lonely post")
      {:ok, %{total_comments: total}} = Ash.aggregate(Post, {:total_comments, :count, [path: [:comments]]})
      assert total == 0
    end
  end

  describe "loading aggregates on records" do
    test "count aggregate returns number of related records per resource" do
      author = create_author()
      post1 = create_post(author, "post1")
      post2 = create_post(author, "post2")
      create_comment(post1, "A")
      create_comment(post1, "B")
      create_comment(post2, "C")

      [p1, p2] = Post |> Ash.read!() |> Ash.load!([:comment_count]) |> Enum.sort_by(& &1.title)
      assert p1.comment_count == 2
      assert p2.comment_count == 1
    end

    test "exists aggregate returns true/false per resource" do
      author = create_author()
      post1 = create_post(author, "with comments")
      _post2 = create_post(author, "without comments")
      create_comment(post1, "a comment")

      posts = Post |> Ash.read!() |> Ash.load!([:has_comments]) |> Enum.sort_by(& &1.title)
      without = Enum.find(posts, &(&1.title == "without comments"))
      with_c  = Enum.find(posts, &(&1.title == "with comments"))

      assert with_c.has_comments == true
      assert without.has_comments == false
    end

    test "first aggregate returns first related field value" do
      author = create_author()
      post = create_post(author, "post")
      create_comment(post, "alpha")
      create_comment(post, "beta")

      [loaded] = Post |> Ash.read!() |> Ash.load!([:first_comment_title])
      assert loaded.first_comment_title in ["alpha", "beta"]
    end

    test "list aggregate returns all related field values" do
      author = create_author()
      post = create_post(author, "post")
      create_comment(post, "alpha")
      create_comment(post, "beta")

      [loaded] = Post |> Ash.read!() |> Ash.load!([:comment_titles])
      assert Enum.sort(loaded.comment_titles) == ["alpha", "beta"]
    end

    test "count is 0 for resource with no related records" do
      author = create_author()
      create_post(author, "empty post")

      [loaded] = Post |> Ash.read!() |> Ash.load!([:comment_count])
      assert loaded.comment_count == 0
    end
  end

  describe "aggregates on embedded struct fields" do
    test "list aggregate returns deserialized typed structs" do
      author = create_author()
      post = create_post(author, "post")
      create_comment_with_dog(post, "a", %DogTypedStruct{name: "Rex", age: 3})
      create_comment_with_dog(post, "b", %DogTypedStruct{name: "Spot", age: 7})

      [loaded] = Post |> Ash.read!() |> Ash.load!([:comment_dogs])
      names = loaded.comment_dogs |> Enum.map(& &1.name) |> Enum.sort()
      assert names == ["Rex", "Spot"]
    end

    test "first aggregate returns a single typed struct" do
      author = create_author()
      post = create_post(author, "post")
      create_comment_with_dog(post, "a", %DogTypedStruct{name: "Rex", age: 3})

      [loaded] = Post |> Ash.read!() |> Ash.load!([:first_comment_dog])
      assert %DogTypedStruct{name: "Rex", age: 3} = loaded.first_comment_dog
    end

    test "list aggregate returns empty list when no structs stored" do
      author = create_author()
      post = create_post(author, "post")
      create_comment(post, "no dog here")

      [loaded] = Post |> Ash.read!() |> Ash.load!([:comment_dogs])
      assert loaded.comment_dogs == []
    end
  end
end
