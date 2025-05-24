defmodule AshNeo4j.DataLayer.Transformer do
  @moduledoc false
  use Spark.Dsl.Transformer

  @verifiers [AshNeo4j.Verifiers.VerifyLabelCamelCase, AshNeo4j.Verifiers.VerifyIdTranslated]

  def transform(dsl) do
    Enum.reduce_while(@verifiers, :ok, fn verifier, _acc ->
      case verifier.verify(dsl) do
        :ok -> {:cont, :ok}
        {error, exception} -> {:halt, {error, exception}}
      end
    end)
  end
end
