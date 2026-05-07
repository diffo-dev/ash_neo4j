# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.CalculationTest do
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

  defp create_author, do: Author |> Ash.Changeset.for_create(:create, %{name: "Author"}) |> Ash.create!()
  defp create_post(author), do: Post |> Ash.Changeset.for_create(:create, %{title: "post", written_by: author.id}) |> Ash.create!()
  defp create_comment(post, title, score) do
    Comment |> Ash.Changeset.for_create(:create, %{title: title, score: score, post_id: post.id}) |> Ash.create!()
  end

  defp create_comment_with_dog(post, title, dog) do
    Comment |> Ash.Changeset.for_create(:create, %{title: title, dog: dog, post_id: post.id}) |> Ash.create!()
  end

  describe "expression calculations" do
    test "scalar expression calculation loads correctly" do
      author = create_author()
      post = create_post(author)
      create_comment(post, "hello", 5)

      [comment] = Comment |> Ash.read!() |> Ash.load!([:score_doubled])
      assert comment.score_doubled == 10
    end

    test "string expression calculation loads correctly" do
      author = create_author()
      post = create_post(author)
      create_comment(post, "hello", 5)

      [comment] = Comment |> Ash.read!() |> Ash.load!([:titled])
      assert comment.titled == "hello (comment)"
    end

    test "nil score gives nil doubled" do
      author = create_author()
      post = create_post(author)
      create_comment(post, "no score", nil)

      [comment] = Comment |> Ash.read!() |> Ash.load!([:score_doubled])
      assert is_nil(comment.score_doubled)
    end

    test "filter on expression calculation" do
      author = create_author()
      post = create_post(author)
      create_comment(post, "low", 3)
      create_comment(post, "high", 10)

      results =
        Comment
        |> Ash.Query.filter(score_doubled > 10)
        |> Ash.read!()

      assert length(results) == 1
      assert hd(results).title == "high"
    end

    test "embedded struct field calculation" do
      author = create_author()
      post = create_post(author)
      create_comment_with_dog(post, "young", %DogTypedStruct{name: "Rex", age: 3})
      create_comment_with_dog(post, "old", %DogTypedStruct{name: "Spot", age: 10})
      create_comment_with_dog(post, "no dog", nil)

      comments = Comment |> Ash.read!() |> Ash.load!([:dog_age])
      by_title = Map.new(comments, &{&1.title, &1.dog_age})

      assert by_title["young"] == 3
      assert by_title["old"] == 10
      assert is_nil(by_title["no dog"])
    end

    test "sort on expression calculation" do
      author = create_author()
      post = create_post(author)
      # "z" has the largest title but the smallest score_doubled (2)
      # "a" has the smallest title but the largest score_doubled (20)
      create_comment(post, "z", 1)
      create_comment(post, "a", 10)

      results =
        Comment
        |> Ash.Query.sort(score_doubled: :asc)
        |> Ash.read!()
        |> Ash.load!([:score_doubled])

      titles = Enum.map(results, & &1.title)
      assert titles == ["z", "a"]
    end
  end
end
