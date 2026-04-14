# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.StateMachineTest do
  @moduledoc false
  use ExUnit.Case, async: false
  alias AshNeo4j.Neo4jHelper
  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Test.Resource.StateMachine
  require Ash.Query

  setup_all do
    BoltyHelper.start()
  end

  setup do
    on_exit(fn ->
      Neo4jHelper.delete_nodes(:StateMachine)
    end)
  end

  describe "StateMachine tests" do
    test "state machine attributes are persisted" do
      state_machine = StateMachine |> Ash.create!(%{})
      assert state_machine.operational_state == :initial
      {:ok, updated_state_machine} = state_machine |> Ash.Changeset.for_update(:start) |> Ash.update()
      assert updated_state_machine.operational_state == :started
    end
  end
end
