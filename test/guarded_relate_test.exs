# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.GuardedRelateTest do
  @moduledoc """
  The `changeset.filter` guard threaded into the relationship write path (#368): a
  to-one `manage_relationship` attach/detach is gated by an optimistic-lock
  predicate against the live source node, in one statement
  (`MATCH (s) WHERE <filter> … MERGE/DELETE`). A guard miss yields zero rows ⇒
  `Ash.Error.Changes.StaleRecord`, never a silent (un)relate. A guard that can't
  push down in full is refused with `AshNeo4j.Error.UnsupportedChangesetFilter` —
  never applied unguarded. Plain Cypher 5, no gate (sibling of #361).

  `Chain` is a to-one (`belongs_to :head`/`:tail`, the relationship attribute on the
  subject), so Ash routes the edge write through this data layer's own update — where
  the guard threads.
  has_many appends are delegated by Ash to the related side under a parent
  filter-read, so they keep the same lock semantics without reaching the relate
  render; covered by Ash's own behaviour, not here.
  """
  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Error.UnsupportedChangesetFilter
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Chain

  use ExUnit.Case, async: false

  require Ash.Expr

  setup_all do
    BoltyHelper.start()
    :ok
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
    :ok
  end

  defp flatten(%{errors: errors}) when is_list(errors), do: Enum.flat_map(errors, &flatten/1)
  defp flatten(e), do: [e]

  defp chain(name), do: Chain |> Ash.Changeset.for_create(:create, %{name: name}) |> Ash.create!()

  defp head_id(chain), do: Chain |> Ash.get!(chain.id) |> Ash.load!(:head_id) |> Map.get(:head_id)

  describe "render: guard lands as a WHERE on the source match" do
    test "relate threads guard right after MATCH (s), g_-prefixed params" do
      query =
        AshNeo4j.Cypher.Query.relate(:Chain, %{uuid: "s1"}, :Chain, %{uuid: "d1"}, :HEAD_TO_TAIL, :incoming,
          guard: [{"name", :==, "b", false}]
        )

      {cypher, params} = AshNeo4j.Cypher.render(query)

      assert cypher =~ ~r/MATCH \(s:Chain \{uuid: \$s_uuid\}\) WHERE s\.name = \$g_s_name_0/
      assert cypher =~ "MERGE (s)<-[r:HEAD_TO_TAIL]-(d)"
      assert params["g_s_name_0"] == "b"
    end

    test "unrelate threads guard after the path MATCH, before DELETE r" do
      query =
        AshNeo4j.Cypher.Query.unrelate(:Chain, %{uuid: "s1"}, :Chain, %{uuid: "d1"}, :HEAD_TO_TAIL, :incoming,
          guard: [{"name", :==, "b", false}]
        )

      {cypher, params} = AshNeo4j.Cypher.render(query)

      assert cypher =~ ~r/WHERE s\.name = \$g_s_name_0 DELETE r/
      assert params["g_s_name_0"] == "b"
    end

    test "no guard renders the original statement unchanged" do
      {cypher, _} =
        AshNeo4j.Cypher.Query.relate(:Chain, %{uuid: "s1"}, :Chain, %{uuid: "d1"}, :HEAD_TO_TAIL, :incoming)
        |> AshNeo4j.Cypher.render()

      refute cypher =~ "WHERE"
    end
  end

  describe "guarded attach (to-one belongs_to)" do
    test "a guard that still holds attaches the edge" do
      a = chain("a")
      b = chain("b")

      assert {:ok, related} =
               b
               |> Ash.Changeset.for_update(:update, %{head_id: a.id})
               |> Ash.Changeset.filter(Ash.Expr.expr(name == "b"))
               |> Ash.update()

      assert related.head_id == a.id
    end

    test "a guard that no longer holds returns StaleRecord, not a silent attach" do
      a = chain("a")
      b = chain("b")

      assert {:error, error} =
               b
               |> Ash.Changeset.for_update(:update, %{head_id: a.id})
               |> Ash.Changeset.filter(Ash.Expr.expr(name == "renamed"))
               |> Ash.update()

      assert Enum.any?(flatten(error), &match?(%Ash.Error.Changes.StaleRecord{}, &1))
      # The edge was not created.
      assert head_id(b) == nil
    end

    test "an un-pushable guard (or) is refused, not applied unguarded" do
      a = chain("a")
      b = chain("b")

      assert {:error, error} =
               b
               |> Ash.Changeset.for_update(:update, %{head_id: a.id})
               |> Ash.Changeset.filter(Ash.Expr.expr(name == "b" or name == "c"))
               |> Ash.update()

      assert Enum.any?(flatten(error), &match?(%UnsupportedChangesetFilter{}, &1))
      # Refused ⇒ no edge.
      assert head_id(b) == nil
    end
  end

  describe "guarded detach (to-one belongs_to)" do
    test "a guard that still holds detaches the edge" do
      a = chain("a")
      b = chain("b")
      {:ok, related} = b |> Ash.Changeset.for_update(:update, %{head_id: a.id}) |> Ash.update()
      assert related.head_id == a.id

      assert {:ok, _} =
               related
               |> Ash.Changeset.for_update(:unrelate, %{head_id: a.id})
               |> Ash.Changeset.filter(Ash.Expr.expr(name == "b"))
               |> Ash.update()

      assert head_id(b) == nil
    end

    test "a guard that no longer holds returns StaleRecord, leaving the edge intact" do
      a = chain("a")
      b = chain("b")
      {:ok, related} = b |> Ash.Changeset.for_update(:update, %{head_id: a.id}) |> Ash.update()

      assert {:error, error} =
               related
               |> Ash.Changeset.for_update(:unrelate, %{head_id: a.id})
               |> Ash.Changeset.filter(Ash.Expr.expr(name == "renamed"))
               |> Ash.update()

      assert Enum.any?(flatten(error), &match?(%Ash.Error.Changes.StaleRecord{}, &1))
      # The edge survives the failed lock.
      assert head_id(b) == a.id
    end
  end
end
