# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Verifiers.VerifyLabelsPascalCase do
  @moduledoc "Verifies that Neo4j labels are PascalCase"
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError
  import AshNeo4j.Util

  @impl true
  def verify(dsl) do
    resource = Verifier.get_persisted(dsl, :module)
    labels = Verifier.get_persisted(dsl, :all_labels)

    cond do
      labels == [] ->
        :ok

      true ->
        if !Enum.all?(labels, &is_valid_node_label?(&1)) do
          {:error,
           DslError.exception(
             module: resource,
             message: "neo4j: neo4j labels must be PascalCase"
           )}
        else
          :ok
        end
    end
  end
end
