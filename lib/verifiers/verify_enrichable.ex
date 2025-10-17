# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Verifiers.VerifyEnrichable do
  @moduledoc "Verifies that relate is unique so relationships are enrichable"
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl) do
    relate = Verifier.get_option(dsl, [:neo4j], :relate, [])
    relate_no_names = Enum.into(relate, [], &Tuple.delete_at(&1, 0))

    if length(relate) == length(Enum.uniq(relate_no_names)) do
      :ok
    else
      resource = Verifier.get_persisted(dsl, :module)

      {:error,
       DslError.exception(
         module: resource,
         message:
           "relate: relationship enrichment not possible, edge_label, edge_direction and destination_label must be unique"
       )}
    end
  end
end
