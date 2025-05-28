defmodule AshNeo4j.DataLayer.Transformer do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer
  alias Spark.Dsl.Verifier

  @verifiers [
    AshNeo4j.Verifiers.VerifyLabelCamelCase,
    AshNeo4j.Verifiers.VerifyIdTranslated,
    AshNeo4j.Verifiers.VerifyRelate,
    AshNeo4j.Verifiers.VerifyProperties,
  ]

  def transform(dsl) do
    verifier_result =
      Enum.reduce_while(@verifiers, :ok, fn verifier, _acc ->
        case verifier.verify(dsl) do
          :ok -> {:cont, :ok}
          {error, exception} -> {:halt, {error, exception}}
        end
      end)

    case verifier_result do
      :ok ->
        {:ok, add_translation(dsl)}
      {error, exception} ->
        {error, exception}
    end
  end

  defp add_translation(dsl) do
    source_attributes =
      Verifier.get_entities(dsl, [:relationships])
      |> Enum.into([], &Map.get(&1, :source_attribute))
    attributes =
      Verifier.get_entities(dsl, [:attributes])
      |> Enum.into([], &Map.get(&1, :name))
      |> Enum.reject(fn name -> name in source_attributes end)
      |> Enum.reject(fn name -> name in Verifier.get_option(dsl, [:neo4j], :skip, []) end)
    translate = Verifier.get_option(dsl, [:neo4j], :translate, [])
    direct = Enum.into(attributes, [], fn attribute -> {attribute, attribute} end)
    translation = Keyword.merge(direct, translate)
    Transformer.set_option(dsl, [:neo4j], :translation, translation)
  end
end
