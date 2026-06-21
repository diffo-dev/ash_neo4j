# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.IdentitiesTest do
  @moduledoc """
  Ash `identities` enforced as Neo4j uniqueness constraints (#20):
  `AshNeo4j.Constraint` renders/creates the constraints; a violation surfaces as an
  Ash identity conflict (`InvalidAttribute`, "has already been taken"), in Ash terms;
  and identities Neo4j can't enforce are refused — at compile time by
  `AshNeo4j.Verifiers.VerifyIdentities`, and by the helper.
  """
  use ExUnit.Case, async: false

  alias AshNeo4j.{BoltyHelper, Constraint, Sandbox}
  alias AshNeo4j.Test.Resource.{Author, Post, Upsert}
  alias AshNeo4j.Test.Util

  setup_all do
    BoltyHelper.start()
    # No sandbox here ⇒ runs as a committed schema change; dropped after the suite.
    {:ok, _} = Constraint.create_constraints(Post)
    on_exit(fn -> Constraint.drop_constraints(Post) end)
    :ok
  end

  defp flatten(%{errors: errors}) when is_list(errors), do: Enum.flat_map(errors, &flatten/1)
  defp flatten(e), do: [e]

  describe "constraint statements" do
    test "primary key (#32) + single-property identity → unparenthesised REQUIRE" do
      assert {:ok,
              [
                "CREATE CONSTRAINT post_pk IF NOT EXISTS FOR (n:Post) REQUIRE n.uuid IS UNIQUE",
                "CREATE CONSTRAINT post_unique_unique IF NOT EXISTS FOR (n:Post) REQUIRE n.unique IS UNIQUE"
              ]} = Constraint.constraint_statements(Post)
    end

    test "composite identity → parenthesised, camelCased properties; pk dedup'd (pk == identity)" do
      # Upsert's primary key is [first_name, surname], the same as identity :full_name,
      # so no separate `_pk` constraint is emitted (#32 dedup).
      assert {:ok,
              [
                "CREATE CONSTRAINT upsert_full_name IF NOT EXISTS FOR (n:Upsert) REQUIRE (n.firstName, n.surname) IS UNIQUE"
              ]} = Constraint.constraint_statements(Upsert)
    end
  end

  describe "compile-time verifier refuses unenforceable identities" do
    test "nils_distinct?: false" do
      Util.assert_compile_time_warning(Spark.Error.DslError, "identities with `nils_distinct?: false`", fn ->
        defmodule NilsNotDistinct do
          use Ash.Resource, domain: AshNeo4j.Test.SRM, data_layer: AshNeo4j.DataLayer

          neo4j do
            label :NilsNotDistinct
          end

          attributes do
            uuid_primary_key :id
            attribute :code, :string, public?: true
          end

          identities do
            identity :by_code, [:code], nils_distinct?: false
          end
        end
      end)
    end

    test "filtered identity (where:)" do
      Util.assert_compile_time_warning(Spark.Error.DslError, "filtered identities", fn ->
        defmodule FilteredIdentity do
          use Ash.Resource, domain: AshNeo4j.Test.SRM, data_layer: AshNeo4j.DataLayer
          require Ash.Expr

          neo4j do
            label :FilteredIdentity
          end

          attributes do
            uuid_primary_key :id
            attribute :code, :string, public?: true
            attribute :active, :boolean, public?: true
          end

          identities do
            identity :by_code, [:code] do
              where expr(active == true)
            end
          end
        end
      end)
    end
  end

  describe "database constraint enforces the identity" do
    setup do
      Sandbox.checkout()
      on_exit(&Sandbox.rollback/0)
      {:ok, author} = Author |> Ash.Changeset.for_create(:create, %{name: "author"}) |> Ash.create()
      %{author: author}
    end

    test "a duplicate surfaces as an Ash identity conflict, not a raw graph error", %{author: author} do
      {:ok, _} =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "p1", unique: "x", written_by: author.id})
        |> Ash.create()

      assert {:error, error} =
               Post
               |> Ash.Changeset.for_create(:create, %{title: "p2", unique: "x", written_by: author.id})
               |> Ash.create()

      errors = flatten(error)
      # In Ash terms: InvalidAttribute on the identity's attribute, "has already been taken".
      assert Enum.any?(
               errors,
               &match?(%Ash.Error.Changes.InvalidAttribute{field: :unique, message: "has already been taken"}, &1)
             )

      # Not the raw graph error.
      refute Enum.any?(errors, &match?(%AshNeo4j.Error.Neo4j{}, &1))
    end
  end
end
