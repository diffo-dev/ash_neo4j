# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Verifiers.VerifyAttributeType do
  @moduledoc "Verifies that attribute types are supported by AshNeo4j.DataLayer"
  use Spark.Dsl.Verifier

  alias AshNeo4j.DataLayer.TypeClassifier

  def verify(dsl_state) do
    resource = Spark.Dsl.Verifier.get_persisted(dsl_state, :module)

    errors =
      dsl_state
      |> Ash.Resource.Info.attributes()
      |> Enum.reduce([], fn attr, errors ->
        case TypeClassifier.invalid_types(attr.type, attr.constraints) do
          [{_, reason, type}] ->
            [
              Spark.Error.DslError.exception(
                module: resource,
                path: [:attributes, attr.name],
                message: "attribute :#{attr.name} requires #{reason} type #{inspect(type)}"
              )
              | errors
            ]

          _ ->
            errors
        end
      end)

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end
end
