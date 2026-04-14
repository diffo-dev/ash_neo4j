# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Verifiers.VerifyPropertiesCamelCase do
  @moduledoc "Verifies that Neo4j properties are camelCase"
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError
  import AshNeo4j.Util

  @impl true
  def verify(dsl) do
    resource = Verifier.get_persisted(dsl, :module)

    translations = Verifier.get_persisted(dsl, :translations, [])
    property_names = Keyword.values(translations)

    cond do
      property_names == [] ->
        :ok

      true ->
        if !Enum.all?(property_names, &is_valid_property_name?(&1)) do
          {:error,
           DslError.exception(
             module: resource,
             message: "neo4j: neo4j property names must be camelCase"
           )}
        else
          :ok
        end
    end
  end
end
