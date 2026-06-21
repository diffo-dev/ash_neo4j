# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.ExpressionFragmentTest do
  @moduledoc """
  The `fragment(...)` Cypher escape hatch in *expressions* (#33) — distinct from Ash
  *resource* fragments (see `AshNeo4j.FragmentTest`). A filter that is a single
  fragment renders straight into the `WHERE`: `?` arguments are attribute refs
  (→ `s.<prop>`) or literals (→ bound `$frag_N` params, injection-safe); raw text is
  author-supplied Cypher. It keeps an un-pushable-but-expressible condition (e.g. an
  APOC function) inside Ash rather than dropping to raw Cypher. A fragment combined
  with other conditions, or a non-ref/non-literal argument, is refused — never
  silently dropped (raw Cypher can't be re-checked in-memory).
  """
  use ExUnit.Case, async: false

  alias AshNeo4j.{BoltyHelper, Sandbox}
  alias AshNeo4j.Error.UnsupportedFilterFragment
  alias AshNeo4j.QueryHelper
  alias AshNeo4j.Resource.Info, as: ResourceInfo
  alias AshNeo4j.Test.Resource.{Author, Post}

  require Ash.Query

  setup_all do
    BoltyHelper.start()
    :ok
  end

  defp mapping, do: ResourceInfo.mapping(Post)
  defp flatten(%{errors: errors}) when is_list(errors), do: Enum.flat_map(errors, &flatten/1)
  defp flatten(e), do: [e]

  describe "render — refs become s.<property>, literals become bound params" do
    test "operator fragment" do
      expression = Ash.Query.filter(Post, fragment("? > ?", score, 5)).filter.expression

      assert {:ok, {"(s.score > $frag_0)", %{"frag_0" => 5}}} =
               QueryHelper.render_fragment(expression, mapping())
    end

    # APOC text functions — the fuzzy/typo-tolerant text-matching use case. Needs APOC
    # on the server to *run*; here we assert the fragment renders the call correctly
    # (the escape-hatch contract: we render faithfully, your server provides APOC).
    test "apoc.text.clean for typo/spacing/case-insensitive matching" do
      expression =
        Ash.Query.filter(Post, fragment("apoc.text.clean(?) = apoc.text.clean(?)", title, "Hello World")).filter.expression

      assert {:ok, {"(apoc.text.clean(s.title) = apoc.text.clean($frag_0))", %{"frag_0" => "Hello World"}}} =
               QueryHelper.render_fragment(expression, mapping())
    end

    test "apoc.text.levenshteinDistance for fuzzy matching" do
      expression =
        Ash.Query.filter(Post, fragment("apoc.text.levenshteinDistance(?, ?) <= ?", title, "John Smith", 2)).filter.expression

      assert {:ok, {"(apoc.text.levenshteinDistance(s.title, $frag_0) <= $frag_1)", %{"frag_0" => "John Smith", "frag_1" => 2}}} =
               QueryHelper.render_fragment(expression, mapping())
    end
  end

  describe "live pushdown" do
    setup do
      Sandbox.checkout()
      on_exit(&Sandbox.rollback/0)
      {:ok, a} = Author |> Ash.Changeset.for_create(:create, %{name: "a"}) |> Ash.create()
      Post |> Ash.Changeset.for_create(:create, %{title: "p7", score: 7, written_by: a.id}) |> Ash.create!()
      Post |> Ash.Changeset.for_create(:create, %{title: "p3", score: 3, written_by: a.id}) |> Ash.create!()
      :ok
    end

    test "operator fragment pushes down and is correct" do
      titles = Post |> Ash.Query.filter(fragment("? > ?", score, 5)) |> Ash.read!() |> Enum.map(& &1.title)
      assert titles == ["p7"]
    end

    test "built-in Cypher function in a fragment" do
      # toLower is built-in (no APOC), proving function-call fragments work live.
      titles = Post |> Ash.Query.filter(fragment("toLower(?) = ?", title, "p7")) |> Ash.read!() |> Enum.map(& &1.title)
      assert titles == ["p7"]
    end
  end

  describe "refuse, never silently drop" do
    setup do
      Sandbox.checkout()
      on_exit(&Sandbox.rollback/0)
      :ok
    end

    test "a fragment combined with another condition is refused" do
      assert {:error, error} =
               Post |> Ash.Query.filter(fragment("? > ?", score, 5) and title == "p7") |> Ash.read()

      assert Enum.any?(flatten(error), &match?(%UnsupportedFilterFragment{reason: :combined}, &1))
    end

    test "a non-literal / non-attribute argument is refused" do
      # `author.name` is a related-field ref, not a plain attribute of Post.
      assert {:error, error} =
               Post |> Ash.Query.filter(fragment("? = ?", author.name, "a")) |> Ash.read()

      assert Enum.any?(flatten(error), &match?(%UnsupportedFilterFragment{}, &1))
    end
  end
end
