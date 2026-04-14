# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Persisters.PersistRelationshipAttributes do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer
  alias Spark.Dsl.Verifier

  @impl true
  def transform(dsl) do
    relationships = Verifier.get_entities(dsl, [:relationships])

    relationship_attributes =
      Enum.into(relationships, [], fn relationship ->
        {Map.get(relationship, :source_attribute), Map.get(relationship, :name)}
      end)

    {:ok, Transformer.persist(dsl, :relationship_attributes, relationship_attributes)}
  end
end
