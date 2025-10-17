# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Transformers.TransformDefaultRelate do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer
  alias Spark.Dsl.Verifier

  @impl true
  def transform(dsl) do
    relationships = Verifier.get_entities(dsl, [:relationships])
    relate = Verifier.get_option(dsl, [:neo4j], :relate, [])

    default_relate =
      Enum.reduce(relationships, [], fn relationship, acc ->
        if List.keyfind(relate, relationship.name, 0) do
          acc
        else
          edge_label = String.to_atom(String.upcase(Atom.to_string(relationship.type)))
          dest_label = String.to_atom(List.last(Module.split(relationship.destination)))
          [{relationship.name, edge_label, :outgoing, dest_label} | acc]
        end
      end)

    transformed_relate = relate ++ default_relate

    {:ok, Transformer.set_option(dsl, [:neo4j], :relate, transformed_relate)}
  end
end
