defmodule AshNeo4j.Transformers.TransformEnsureLabelled do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer
  alias Spark.Dsl.Verifier

  @impl true
  def transform(dsl) do
    {:ok, ensure_labelled(dsl)}
  end

  defp ensure_labelled(dsl) do
    case Verifier.get_option(dsl, [:neo4j], :label, nil) do
      nil ->
        resource = Verifier.get_persisted(dsl, :module)
        module = String.to_atom(List.last(Module.split(resource)))
        Transformer.set_option(dsl, [:neo4j], :label, module)

      _ ->
        dsl
    end
  end
end
