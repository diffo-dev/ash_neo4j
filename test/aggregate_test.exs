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
  require Ash.Expr

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

  defp create_comment_with_score(post, title, score) do
    Comment
    |> Ash.Changeset.for_create(:create, %{title: title, post_id: post.id, score: score})
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
      with_c = Enum.find(posts, &(&1.title == "with comments"))

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

  describe "expr aggregates (Ash.Query.Calculation field, programmatic API)" do
    test "sum expr totals a scalar field across all related records" do
      author = create_author()
      post1 = create_post(author, "post1")
      post2 = create_post(author, "post2")
      create_comment_with_score(post1, "a", 10)
      create_comment_with_score(post1, "b", 25)
      create_comment_with_score(post2, "c", 5)

      {:ok, %{total_score: total}} =
        Ash.aggregate(Post, {:total_score, :sum, [path: [:comments], expr: Ash.Expr.expr(score), expr_type: :integer]})

      assert total == 40
    end

    test "sum expr returns nil default when no related records" do
      create_author() |> create_post("empty post")

      {:ok, %{total_score: total}} =
        Ash.aggregate(Post, {:total_score, :sum, [path: [:comments], expr: Ash.Expr.expr(score), expr_type: :integer]})

      assert is_nil(total)
    end

    test "sum expr on embedded struct field navigates via Ash expression" do
      author = create_author()
      post = create_post(author, "post")
      create_comment_with_dog(post, "a", %DogTypedStruct{name: "Rex", age: 3})
      create_comment_with_dog(post, "b", %DogTypedStruct{name: "Spot", age: 7})

      {:ok, %{total_dog_age: total}} =
        Ash.aggregate(
          Post,
          {:total_dog_age, :sum, [path: [:comments], expr: Ash.Expr.expr(get_path(dog, [:age])), expr_type: :integer]}
        )

      assert total == 10
    end
  end

  describe "aggregate names with ? suffix (#251 — must not produce invalid Cypher)" do
    test "exists aggregate named with ? suffix returns correct boolean" do
      author = create_author()
      post_with = create_post(author, "with comments")
      _post_without = create_post(author, "without comments")
      create_comment(post_with, "a comment")

      [with_c, without_c] = Post |> Ash.read!() |> Ash.load!([:has_comments?]) |> Enum.sort_by(& &1.title)

      assert with_c.has_comments? == true
      assert without_c.has_comments? == false
    end
  end

  describe "filtered aggregates (#252 — filter must not be silently dropped)" do
    test "first aggregate with filter returns the matching record's field, not whichever comes first" do
      author = create_author()
      post = create_post(author, "post")
      # Create beta first so Neo4j is likely to return it first without a filter
      create_comment(post, "beta")
      create_comment(post, "alpha")

      [loaded] = Post |> Ash.read!() |> Ash.load!([:first_alpha_comment_title])
      assert loaded.first_alpha_comment_title == "alpha"
    end

    test "count aggregate with filter counts only matching records" do
      author = create_author()
      post1 = create_post(author, "post1")
      post2 = create_post(author, "post2")
      create_comment(post1, "alpha")
      create_comment(post1, "beta")
      create_comment(post1, "alpha")
      create_comment(post2, "beta")

      [p1, p2] = Post |> Ash.read!() |> Ash.load!([:alpha_comment_count]) |> Enum.sort_by(& &1.title)
      assert p1.alpha_comment_count == 2
      assert p2.alpha_comment_count == 0
    end

    test "exists aggregate with filter is false when only non-matching records exist" do
      author = create_author()
      post = create_post(author, "post")
      create_comment(post, "beta")

      [loaded] = Post |> Ash.read!() |> Ash.load!([:has_alpha_comment])
      assert loaded.has_alpha_comment == false
    end

    test "exists aggregate with filter is true when a matching record exists" do
      author = create_author()
      post = create_post(author, "post")
      create_comment(post, "beta")
      create_comment(post, "alpha")

      [loaded] = Post |> Ash.read!() |> Ash.load!([:has_alpha_comment])
      assert loaded.has_alpha_comment == true
    end

    test "list aggregate with filter returns only matching field values" do
      author = create_author()
      post = create_post(author, "post")
      create_comment(post, "alpha")
      create_comment(post, "beta")
      create_comment(post, "alpha")

      [loaded] = Post |> Ash.read!() |> Ash.load!([:alpha_comment_titles])
      assert Enum.sort(loaded.alpha_comment_titles) == ["alpha", "alpha"]
    end

    test "count with filter returns 0 for post with no comments" do
      author = create_author()
      create_post(author, "empty post")

      [loaded] = Post |> Ash.read!() |> Ash.load!([:alpha_comment_count])
      assert loaded.alpha_comment_count == 0
    end

    test "multiple posts each see only their own filtered count" do
      author = create_author()
      post1 = create_post(author, "aaa")
      post2 = create_post(author, "bbb")
      create_comment(post1, "alpha")
      create_comment(post1, "alpha")
      create_comment(post1, "beta")
      create_comment(post2, "beta")
      create_comment(post2, "beta")

      [p1, p2] =
        Post |> Ash.read!() |> Ash.load!([:alpha_comment_count, :has_alpha_comment]) |> Enum.sort_by(& &1.title)

      assert p1.alpha_comment_count == 2
      assert p1.has_alpha_comment == true
      assert p2.alpha_comment_count == 0
      assert p2.has_alpha_comment == false
    end
  end

  describe "scalar filter pushdown (#253 — == filters pushed to Cypher WHERE)" do
    test "count with integer == filter counts only matching records" do
      author = create_author()
      post1 = create_post(author, "post1")
      post2 = create_post(author, "post2")
      create_comment_with_score(post1, "a", 10)
      create_comment_with_score(post1, "b", 5)
      create_comment_with_score(post1, "c", 10)
      create_comment_with_score(post2, "d", 5)

      [p1, p2] = Post |> Ash.read!() |> Ash.load!([:high_score_count]) |> Enum.sort_by(& &1.title)
      assert p1.high_score_count == 2
      assert p2.high_score_count == 0
    end

    test "exists with integer == filter is false when no matching records" do
      author = create_author()
      post = create_post(author, "post")
      create_comment_with_score(post, "a", 5)

      [loaded] = Post |> Ash.read!() |> Ash.load!([:has_high_score])
      assert loaded.has_high_score == false
    end

    test "exists with integer == filter is true when a matching record exists" do
      author = create_author()
      post = create_post(author, "post")
      create_comment_with_score(post, "a", 5)
      create_comment_with_score(post, "b", 10)

      [loaded] = Post |> Ash.read!() |> Ash.load!([:has_high_score])
      assert loaded.has_high_score == true
    end

    test "sum with integer == filter totals only matching records" do
      author = create_author()
      post = create_post(author, "post")
      create_comment_with_score(post, "a", 10)
      create_comment_with_score(post, "b", 5)
      create_comment_with_score(post, "c", 10)

      [loaded] = Post |> Ash.read!() |> Ash.load!([:high_score_total])
      assert loaded.high_score_total == 20
    end

    test "count with integer == filter returns 0 for post with no comments" do
      author = create_author()
      create_post(author, "empty post")

      [loaded] = Post |> Ash.read!() |> Ash.load!([:high_score_count])
      assert loaded.high_score_count == 0
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
