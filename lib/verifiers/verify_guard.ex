# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Verifiers.VerifyGuard do
  @moduledoc "Verifies that each guard is a node relationship meeting Neo4j conventions"
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError
  import AshNeo4j.Util
  @valid_edge_directions [:incoming, :outgoing, :any]

  @impl true
  def verify(dsl) do
    resource = Verifier.get_persisted(dsl, :module)
    guard = Verifier.get_option(dsl, [:neo4j], :guard, [])

    case invalid_edge_labels =
           Enum.reduce(guard, [], fn {edge_label, _edge_direction, _destination_label}, acc ->
             if is_valid_edge_label?(edge_label) do
               acc
             else
               [edge_label | acc]
             end
           end) do
      [] ->
        case invalid_edge_directions =
               Enum.reduce(guard, [], fn {_edge_label, edge_direction, _destination_label}, acc ->
                 if edge_direction in @valid_edge_directions do
                   acc
                 else
                   [edge_direction | acc]
                 end
               end) do
          [] ->
            case invalid_destination_labels =
                   Enum.reduce(guard, [], fn {_edge_label, _edge_direction, destination_label}, acc ->
                     if is_valid_node_label?(destination_label) do
                       acc
                     else
                       [destination_label | acc]
                     end
                   end) do
              [] ->
                :ok

              _ ->
                {:error,
                 DslError.exception(
                   module: resource,
                   message:
                     "guard: destination labels must be PascalCase, invalid destination labels: #{inspect(invalid_destination_labels)} "
                 )}
            end

          _ ->
            {:error,
             DslError.exception(
               module: resource,
               message: "guard: invalid edge directions: #{inspect(invalid_edge_directions)}"
             )}
        end

      _ ->
        {:error,
         DslError.exception(
           module: resource,
           message:
             "guard: edge labels must be upper case and may have an underscore, invalid edge labels: #{inspect(invalid_edge_labels)}"
         )}
    end
  end
end
