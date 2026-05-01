# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.TransactionTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Test.Resource.Type

  setup_all do
    BoltyHelper.start()
  end

  setup do
    on_exit(fn ->
      Type |> Ash.read!() |> Enum.each(&Ash.destroy!(&1))
    end)
  end

  test "in_transaction? is true during a transaction" do
    Ash.transaction(Type, fn ->
      assert Ash.DataLayer.in_transaction?(Type)
    end)
  end

  test "in_transaction? is false outside a transaction" do
    refute Ash.DataLayer.in_transaction?(Type)
  end

  test "commits on success" do
    {:ok, _} =
      Ash.transaction(Type, fn ->
        Type |> Ash.Changeset.for_create(:create, %{string: "committed"}) |> Ash.create!()
      end)

    assert length(Ash.read!(Type)) == 1
  end

  test "rolls back on DataLayer.rollback" do
    {:error, error} =
      Ash.transaction(Type, fn ->
        Type |> Ash.Changeset.for_create(:create, %{string: "will rollback"}) |> Ash.create!()
        Ash.DataLayer.rollback(Type, :intentional)
      end)

    assert error.error =~ "intentional"
    assert Ash.read!(Type) == []
  end
end
