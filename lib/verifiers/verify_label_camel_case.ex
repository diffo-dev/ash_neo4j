defmodule AshNeo4j.Verifiers.VerifyLabelCamelCase do
  @moduledoc "Verifies that the label is camelcase"
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError
  @regex ~r/^[A-Z][a-zA-Z]*$/

  @impl true
  def verify(dsl) do
    resource = Verifier.get_persisted(dsl, :module)
    label = Verifier.get_option(dsl, [:neo4j], :label, nil)
    cond do
      label == nil ->
        {:error,
          DslError.exception(
            module: resource,
            message: "label: missing"
        )}

      Regex.match?(@regex, Atom.to_string(label)) ->
        :ok

      true ->
        {:error,
          DslError.exception(
            module: resource,
            message: "label: neo4j label must be CamelCase"
          )}
    end
  end
end
