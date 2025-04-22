defmodule AshNeo4j.Ex4j.Helper do
  use Ex4j.Cypher

  def match_nodes(node) do
    match(node, as: :n)
    |> return(:n)
    |> run()
  end
end
