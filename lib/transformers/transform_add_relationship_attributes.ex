defmodule AshNeo4j.Transformers.TransformAddRelationshipAttributes do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer
  alias Spark.Dsl.Verifier

  def transform(dsl) do
    {:ok, add_relationship_attributes(dsl)}
  end

  defp add_relationship_attributes(dsl) do
    relationships = Verifier.get_entities(dsl, [:relationships])
    relationship_attributes = Enum.into(relationships, [],
      fn relationship ->
        {Map.get(relationship, :source_attribute), Map.get(relationship, :name)}
      end)
    Transformer.set_option(dsl, [:neo4j], :relationship_attributes, relationship_attributes)
  end
end
