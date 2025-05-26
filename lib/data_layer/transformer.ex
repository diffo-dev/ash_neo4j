defmodule AshNeo4j.DataLayer.Transformer do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

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
          {:ok, add_translations(dsl)}
        {error, exception} ->
          {error, exception}
      end
  end

  defp add_translations(dsl) do
    store = AshNeo4j.DataLayer.Info.store(dsl)
    translate = AshNeo4j.DataLayer.Info.translate(dsl)
    attributes = Enum.into(store, [], fn attribute -> {attribute, attribute} end)
    translation = Keyword.merge(attributes, translate)
    Transformer.set_option(dsl, [:neo4j], :translation, translation)
  end
end
