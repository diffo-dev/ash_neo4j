# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.AtomicUpdateTest do
  @moduledoc """
  Atomic updates (#361): `changeset.atomics` are evaluated against the live node in
  a single `SET`, no read-decide-in-Elixir round-trip. Renders arithmetic,
  string concat/`trim` (Ash's string cast), and `if/3 ⇒ CASE`. An atomic we can't
  render is refused with `AshNeo4j.Error.UnsupportedAtomic` rather than mis-written.
  """
  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Error.UnsupportedAtomic
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Comment
  alias AshNeo4j.Test.Resource.Specification

  use ExUnit.Case, async: false

  require Ash.Expr

  setup_all do
    BoltyHelper.start()
    :ok
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  defp flatten(%{errors: errors}) when is_list(errors), do: Enum.flat_map(errors, &flatten/1)
  defp flatten(e), do: [e]

  defp atomic(comment, field, expr) do
    comment
    |> Ash.Changeset.for_update(:update, %{})
    |> Ash.Changeset.atomic_update(field, expr)
    |> Ash.update()
  end

  test "an arithmetic atomic increments against the live value" do
    comment = Comment |> Ash.create!(%{title: "t", score: 1})

    assert {:ok, updated} = atomic(comment, :score, Ash.Expr.expr(score + 1))
    assert updated.score == 2
  end

  test "an if/3 atomic renders to CASE and decrements only when positive" do
    comment = Comment |> Ash.create!(%{title: "t", score: 1})
    expr = Ash.Expr.expr(if score > 0, do: score - 1, else: 0)

    assert {:ok, once} = atomic(comment, :score, expr)
    assert once.score == 0

    assert {:ok, twice} = atomic(once, :score, expr)
    assert twice.score == 0
  end

  test "an atomic combines with a changeset.filter guard" do
    comment = Comment |> Ash.create!(%{title: "t", score: 5})

    result =
      comment
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.Changeset.atomic_update(:score, Ash.Expr.expr(score + 1))
      |> Ash.Changeset.filter(Ash.Expr.expr(score == 5))
      |> Ash.update()

    assert {:ok, updated} = result
    assert updated.score == 6

    # The same guard now misses (score is 6) ⇒ StaleRecord, no write.
    stale =
      updated
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.Changeset.atomic_update(:score, Ash.Expr.expr(score + 1))
      |> Ash.Changeset.filter(Ash.Expr.expr(score == 5))
      |> Ash.update()

    assert {:error, error} = stale
    assert Enum.any?(flatten(error), &match?(%Ash.Error.Changes.StaleRecord{}, &1))
    assert Comment |> Ash.get!(updated.id) |> Map.get(:score) == 6
  end

  test "a string-concat atomic renders (Ash's trim/empty-⇒-nil cast)" do
    comment = Comment |> Ash.create!(%{title: "draft", score: 1})

    assert {:ok, updated} = atomic(comment, :title, Ash.Expr.expr(title <> "!"))
    assert updated.title == "draft!"
  end

  test "a string if/3 atomic renders to CASE against the live value" do
    comment = Comment |> Ash.create!(%{title: "draft", score: 1})
    expr = Ash.Expr.expr(if title == "draft", do: "active", else: title)

    assert {:ok, updated} = atomic(comment, :title, expr)
    assert updated.title == "active"
  end

  test "an atom (enum) if/3 atomic renders to CASE and transitions against the live value" do
    spec = Specification |> Ash.create!(%{type: :service})
    expr = Ash.Expr.expr(if type == :service, do: :resource, else: type)

    assert {:ok, updated} = atomic(spec, :type, expr)
    assert updated.type == :resource

    # Re-running is a no-op: the live value is now :resource, so the else branch
    # preserves it (the atom round-trips through its stored string form).
    assert {:ok, again} = atomic(updated, :type, expr)
    assert again.type == :resource
  end

  test "an atomic using an unsupported function is refused, not mis-written" do
    comment = Comment |> Ash.create!(%{title: "Draft", score: 1})

    assert {:error, error} = atomic(comment, :title, Ash.Expr.expr(string_downcase(title)))
    assert Enum.any?(flatten(error), &match?(%UnsupportedAtomic{}, &1))
    assert Comment |> Ash.get!(comment.id) |> Map.get(:title) == "Draft"
  end
end
