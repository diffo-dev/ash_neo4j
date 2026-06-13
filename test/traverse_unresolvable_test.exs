# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.TraverseUnresolvableTest do
  @moduledoc """
  A `traverse(^chain, …)` filter that can't be formed returns a Splode
  `AshNeo4j.Error.UnresolvableTraversal` (#342) — never a fabricated/unfiltered
  query — and `:reason` distinguishes the failure mode.
  """
  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Error.UnresolvableTraversal
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Post

  use ExUnit.Case, async: true

  require Ash.Query

  setup_all do
    BoltyHelper.start()
    Enum.each([AshNeo4j.Test.Resource.Author], &Code.ensure_loaded!/1)
    :ok
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  defp flatten(%{errors: errors} = e) when is_list(errors), do: [e | Enum.flat_map(errors, &flatten/1)]
  defp flatten(e), do: [e]

  defp reason_of({:error, error}) do
    error
    |> flatten()
    |> Enum.find_value(fn
      %UnresolvableTraversal{reason: reason} -> reason
      _ -> nil
    end)
  end

  test "unresolved_reached: an explicit edge to an unknown label can't type the reached node" do
    chain = [{:reverse, {:edge, :WROTE, :Nonexistent}}]
    result = Post |> Ash.Query.filter(traverse(^chain, :name) == "x") |> Ash.read()
    assert reason_of(result) == :unresolved_reached
  end

  test "unmapped_property: the reached Author is typed but :not_a_field isn't one of its properties" do
    chain = [{:reverse, {:edge, :WROTE, :Author}}]
    result = Post |> Ash.Query.filter(traverse(^chain, :not_a_field) == "x") |> Ash.read()
    assert reason_of(result) == :unmapped_property
  end
end
