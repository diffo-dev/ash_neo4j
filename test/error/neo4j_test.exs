# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Error.Neo4jTest do
  @moduledoc """
  `AshNeo4j.Error.Neo4j.from_bolt/1` (#358) classifies a `%Bolty.Error{}` by its
  Neo4j status code and preserves code + message, so a server failure surfaces
  as the real error instead of a generic string (the read/write paths thread it
  via `run_cypher_query` / `create_node` / `update_node`).
  """
  use ExUnit.Case, async: true

  alias AshNeo4j.Error.Neo4j

  defp bolt(code, msg \\ "boom"), do: %Bolty.Error{module: Bolty, code: :error, bolt: %{code: code, message: msg}}

  test "a constraint violation classifies as :constraint" do
    err = Neo4j.from_bolt(bolt("Neo.ClientError.Schema.ConstraintValidationFailed", "already exists"))
    assert %Neo4j{category: :constraint, neo4j_code: "Neo.ClientError.Schema.ConstraintValidationFailed"} = err
    assert Neo4j.constraint_violation?(err)
  end

  test "a transient error classifies as :transient" do
    err = Neo4j.from_bolt(bolt("Neo.TransientError.Transaction.DeadlockDetected"))
    assert %Neo4j{category: :transient} = err
    refute Neo4j.constraint_violation?(err)
  end

  test "a statement (syntax) error classifies as :statement" do
    assert %Neo4j{category: :statement} = Neo4j.from_bolt(bolt("Neo.ClientError.Statement.SyntaxError"))
  end

  test "a security error classifies as :security" do
    assert %Neo4j{category: :security} = Neo4j.from_bolt(bolt("Neo.ClientError.Security.Forbidden"))
  end

  test "an unrecognised code classifies as :other" do
    assert %Neo4j{category: :other} = Neo4j.from_bolt(bolt("Neo.DatabaseError.General.UnknownError"))
  end

  test "the message preserves the Neo4j code and message" do
    msg = Exception.message(Neo4j.from_bolt(bolt("Neo.ClientError.Schema.ConstraintValidationFailed", "already exists")))
    assert msg =~ "ConstraintValidationFailed"
    assert msg =~ "already exists"
  end

  test "a non-Bolty error term is wrapped as :other, code nil" do
    assert %Neo4j{category: :other, neo4j_code: nil, neo4j_message: "raw failure"} = Neo4j.from_bolt("raw failure")
  end
end
