# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Verifiers.VerifyRelate do
  @moduledoc "Verifies that each relate relates to a relationship, and that the edge labels meets Neo4j conventions"
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError
  @edge_label_regex ~r/^[A-Z]+(_[A-Z]+)*$/
  @node_label_regex ~r/^[A-Z][a-zA-Z0-9]*$/

  @impl true
  def verify(dsl) do
    resource = Verifier.get_persisted(dsl, :module)
    relate = Verifier.get_option(dsl, [:neo4j], :relate, [])
    relationships = Verifier.get_entities(dsl, [:relationships])

    if length(relate) == length(relationships) do
      case invalid_edge_labels =
             Enum.reduce(relate, [], fn {_relationship_name, edge_label, _edge_direction, _destination_label}, acc ->
               if Regex.match?(@edge_label_regex, Atom.to_string(edge_label)) do
                 acc
               else
                 [to_string(edge_label) | acc]
               end
             end) do
        [] ->
          relationships = Verifier.get_entities(dsl, [:relationships])
          relationship_names = Enum.into(relationships, [], &Map.get(&1, :name))

          case mismatched_relationship_names =
                 Enum.reduce(relate, [], fn {relationship_name, _edge_label, _edge_direction, _destination_label},
                                            acc ->
                   if relationship_name in relationship_names do
                     acc
                   else
                     [to_string(relationship_name) | acc]
                   end
                 end) do
            [] ->
              case invalid_edge_directions =
                     Enum.reduce(relate, [], fn {_relationship_name, _edge_label, edge_direction, _destination_label},
                                                acc ->
                       if edge_direction in [:incoming, :outgoing] do
                         acc
                       else
                         [to_string(edge_direction) | acc]
                       end
                     end) do
                [] ->
                  case invalid_destination_labels =
                         Enum.reduce(relate, [], fn {_relationship_name, _edge_label, _edge_direction,
                                                     destination_label},
                                                    acc ->
                           if Regex.match?(@node_label_regex, Atom.to_string(destination_label)) do
                             acc
                           else
                             [to_string(destination_label) | acc]
                           end
                         end) do
                    [] ->
                      :ok

                    _ ->
                      {:error,
                       DslError.exception(
                         module: resource,
                         message:
                           "relate: destination labels must be PascalCase, invalid destination labels: #{invalid_destination_labels}"
                       )}
                  end

                _ ->
                  {:error,
                   DslError.exception(
                     module: resource,
                     message:
                       "relate: edge directions must be :incoming or :outgoing, invalid edge directions: #{invalid_edge_directions}"
                   )}
              end

            _ ->
              {:error,
               DslError.exception(
                 module: resource,
                 message:
                   "relate: relationship names must match the name of a relationship, mismatched relationship names: #{mismatched_relationship_names}"
               )}
          end

        _ ->
          {:error,
           DslError.exception(
             module: resource,
             message:
               "relate: edge labels must be upper case and may have an underscore, invalid edge labels: #{invalid_edge_labels}"
           )}
      end
    else
      {:error,
       DslError.exception(
         module: resource,
         message: "relate: relate and relationships have different number of entries"
       )}
    end
  end
end
