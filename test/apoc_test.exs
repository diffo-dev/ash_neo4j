# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.ApocTest do
  @moduledoc """
  APOC availability healthcheck and a round-trip `apoc.*` `fragment(...)` (#386).

  Installing APOC is the operator's job; AshNeo4j only reports it
  (`AshNeo4j.BoltyHelper.apoc_available?/0,1`). The default `Bolt` server is plain
  Community (no APOC), so the healthcheck reads `false` there; the `:apoc`-tagged
  tests route to the `BoltApoc` pool (Neo4j + APOC, `docker-compose` `neo4j-apoc`)
  and are excluded by default — like `:cypher25` / `:bolt6`.
  """
  use ExUnit.Case, async: false

  alias AshNeo4j.{BoltyHelper, Sandbox}
  alias AshNeo4j.Test.Resource.{Author, Post}

  require Ash.Query

  setup_all do
    BoltyHelper.start()
    :ok
  end

  test "apoc_available? is false on the plain default server" do
    refute BoltyHelper.apoc_available?(Bolt)
    refute BoltyHelper.apoc_available?()
  end

  describe "with APOC (BoltApoc pool)" do
    @describetag :apoc

    setup do
      Process.put(:ash_neo4j_pool, BoltApoc)
      Sandbox.checkout()
      on_exit(&Sandbox.rollback/0)
      {:ok, a} = Author |> Ash.Changeset.for_create(:create, %{name: "a"}) |> Ash.create()
      %{author: a}
    end

    test "apoc_available? is true" do
      assert BoltyHelper.apoc_available?(BoltApoc)
    end

    test "a real apoc.* fragment round-trips and is correct", %{author: a} do
      # apoc.text.clean strips non-word chars and lowercases, so "Hello, World!"
      # and "hello world" normalise to the same value — typo/spacing/case-tolerant.
      Post |> Ash.Changeset.for_create(:create, %{title: "Hello, World!", written_by: a.id}) |> Ash.create!()
      Post |> Ash.Changeset.for_create(:create, %{title: "Something else", written_by: a.id}) |> Ash.create!()

      titles =
        Post
        |> Ash.Query.filter(fragment("apoc.text.clean(?) = apoc.text.clean(?)", title, "hello world"))
        |> Ash.read!()
        |> Enum.map(& &1.title)

      assert titles == ["Hello, World!"]
    end
  end
end
