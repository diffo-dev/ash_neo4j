# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.AtomicUpdateGuardTest do
  @moduledoc """
  The `changeset.filter` "only-update-if" guard (#361). An update applies only to a
  row still matching the filter; a miss returns `Ash.Error.Changes.StaleRecord`
  rather than silently writing. A guard that can't be pushed down in full is
  refused with `AshNeo4j.Error.UnsupportedUpdateFilter` — never applied unguarded.
  """
  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Error.UnsupportedChangesetFilter
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.ThingNote

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

  defp guarded_update(note, attrs, guard) do
    note
    |> Ash.Changeset.for_update(:update, attrs)
    |> Ash.Changeset.filter(guard)
    |> Ash.update()
  end

  test "a guard that still holds applies the update" do
    note = ThingNote |> Ash.create!(%{body: "draft"})

    assert {:ok, updated} = guarded_update(note, %{body: "active"}, Ash.Expr.expr(body == "draft"))
    assert updated.body == "active"
  end

  test "a guard that no longer holds returns StaleRecord, not a silent write" do
    note = ThingNote |> Ash.create!(%{body: "draft"})
    {:ok, active} = guarded_update(note, %{body: "active"}, Ash.Expr.expr(body == "draft"))

    # `active` is now body: "active"; the same draft guard must miss.
    assert {:error, error} = guarded_update(active, %{body: "archived"}, Ash.Expr.expr(body == "draft"))
    assert Enum.any?(flatten(error), &match?(%Ash.Error.Changes.StaleRecord{}, &1))

    # The row was not written.
    assert ThingNote |> Ash.get!(active.id) |> Map.get(:body) == "active"
  end

  test "a conjunction of supported predicates pushes down" do
    note = ThingNote |> Ash.create!(%{body: "draft"})

    guard = Ash.Expr.expr(body == "draft" and id == ^note.id)
    assert {:ok, updated} = guarded_update(note, %{body: "active"}, guard)
    assert updated.body == "active"
  end

  test "an un-pushable guard (or) is refused, not applied unguarded" do
    note = ThingNote |> Ash.create!(%{body: "draft"})

    guard = Ash.Expr.expr(body == "draft" or body == "review")
    assert {:error, error} = guarded_update(note, %{body: "active"}, guard)
    assert Enum.any?(flatten(error), &match?(%UnsupportedChangesetFilter{}, &1))

    # Refused, so the row is unchanged.
    assert ThingNote |> Ash.get!(note.id) |> Map.get(:body) == "draft"
  end

  test "a filtered destroy whose lock no longer holds returns StaleRecord, not a delete" do
    note = ThingNote |> Ash.create!(%{body: "draft"})

    result =
      note
      |> Ash.Changeset.for_destroy(:destroy)
      |> Ash.Changeset.filter(Ash.Expr.expr(body == "review"))
      |> Ash.destroy()

    assert {:error, error} = result
    assert Enum.any?(flatten(error), &match?(%Ash.Error.Changes.StaleRecord{}, &1))

    # The optimistic lock missed (body is "draft", not "review") — row preserved.
    assert ThingNote |> Ash.get!(note.id) |> Map.get(:body) == "draft"
  end

  test "a filtered destroy whose lock holds deletes the row" do
    note = ThingNote |> Ash.create!(%{body: "draft"})

    assert :ok =
             note
             |> Ash.Changeset.for_destroy(:destroy)
             |> Ash.Changeset.filter(Ash.Expr.expr(body == "draft"))
             |> Ash.destroy()

    assert {:error, _} = ThingNote |> Ash.get(note.id)
  end

  test "an un-pushable destroy filter is refused, not applied unguarded" do
    note = ThingNote |> Ash.create!(%{body: "draft"})

    result =
      note
      |> Ash.Changeset.for_destroy(:destroy)
      |> Ash.Changeset.filter(Ash.Expr.expr(body == "draft" or body == "review"))
      |> Ash.destroy()

    assert {:error, error} = result
    assert Enum.any?(flatten(error), &match?(%UnsupportedChangesetFilter{}, &1))
    assert ThingNote |> Ash.get!(note.id) |> Map.get(:body) == "draft"
  end
end
