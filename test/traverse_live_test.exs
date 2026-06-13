# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.TraverseLiveTest do
  @moduledoc false
  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Author
  alias AshNeo4j.Test.Resource.Comment
  alias AshNeo4j.Test.Resource.Post

  use ExUnit.Case, async: true

  require Ash.Query

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  test "1-hop forward relationship traversal: authors who wrote a post scoring > 50" do
    alice = Ash.create!(Author, %{name: "Alice"})
    bob = Ash.create!(Author, %{name: "Bob"})
    Ash.create!(Post, %{title: "hit", score: 90, written_by: alice.id})
    Ash.create!(Post, %{title: "miss", score: 10, written_by: bob.id})

    chain = [{:forward, :posts}]

    names =
      Author
      |> Ash.Query.filter(traverse(^chain, :score) > 50)
      |> Ash.read!()
      |> Enum.map(& &1.name)

    assert names == ["Alice"]
  end

  test "2-hop forward traversal: authors with a high-scoring comment on one of their posts" do
    alice = Ash.create!(Author, %{name: "Alice"})
    bob = Ash.create!(Author, %{name: "Bob"})
    {:ok, alice_post} = Post |> Ash.Changeset.for_create(:create, %{title: "ap", written_by: alice.id}) |> Ash.create()
    {:ok, bob_post} = Post |> Ash.Changeset.for_create(:create, %{title: "bp", written_by: bob.id}) |> Ash.create()
    cold = Ash.create!(Comment, %{title: "cold", score: 5})
    hot = Ash.create!(Comment, %{title: "hot", score: 100})
    Ash.update!(Ash.Changeset.for_update(alice_post, :update, add_comments: [cold.id]))
    Ash.update!(Ash.Changeset.for_update(bob_post, :update, add_comments: [hot.id]))

    # Author -[:WROTE]-> Post <-[:BELONGS_TO]- Comment
    chain = [{:forward, :posts}, {:forward, :comments}]

    names =
      Author
      |> Ash.Query.filter(traverse(^chain, :score) > 50)
      |> Ash.read!()
      |> Enum.map(& &1.name)

    assert names == ["Bob"]
  end

  test "reverse hop with an explicit edge selector: posts written by a given author" do
    alice = Ash.create!(Author, %{name: "Alice"})
    bob = Ash.create!(Author, %{name: "Bob"})
    {:ok, _} = Post |> Ash.Changeset.for_create(:create, %{title: "by-alice", written_by: alice.id}) |> Ash.create()
    {:ok, _} = Post |> Ash.Changeset.for_create(:create, %{title: "by-bob", written_by: bob.id}) |> Ash.create()

    # Post <-[:WROTE]- Author — walk the WROTE edge in reverse via an explicit selector
    chain = [{:reverse, {:edge, :WROTE, :Author}}]

    titles =
      Post
      |> Ash.Query.filter(traverse(^chain, :name) == "Alice")
      |> Ash.read!()
      |> Enum.map(& &1.title)

    assert titles == ["by-alice"]
  end

  test "reverse-terminal field access is typed through the real mapping, not a camelCase guess (#336)" do
    # Author.pen_name is sourced to the property `writerAlias` (not `penName`),
    # so this only matches if the reverse-reached node resolves to Author and
    # uses its mapping. The old camelCase fallback queried `penName` — and the
    # earlier `:name` reverse test passed only because `:name -> "name"` by luck.
    ghost = Ash.create!(Author, %{name: "G. Writer", pen_name: "Ghost"})
    public = Ash.create!(Author, %{name: "P. Writer", pen_name: "Public"})
    {:ok, _} = Post |> Ash.Changeset.for_create(:create, %{title: "ghosted", written_by: ghost.id}) |> Ash.create()
    {:ok, _} = Post |> Ash.Changeset.for_create(:create, %{title: "open", written_by: public.id}) |> Ash.create()

    chain = [{:reverse, {:edge, :WROTE, :Author}}]

    titles =
      Post
      |> Ash.Query.filter(traverse(^chain, :pen_name) == "Ghost")
      |> Ash.read!()
      |> Enum.map(& &1.title)

    assert titles == ["ghosted"]
  end
end
