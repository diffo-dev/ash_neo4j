defmodule AshNeo4j.Verifiers.VerifyRelate do
  @moduledoc "Verifies that a relate relates to a relationship, and that the edge label meets Neo4j conventions"
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError
  @regex ~r/^[A-Z]*_?[A-Z]*$/

  @impl true
  def verify(dsl) do
    resource = Verifier.get_persisted(dsl, :module)
    relate = Verifier.get_option(dsl, [:neo4j], :relate, [])
    relationships = Verifier.get_entities(dsl, [:relationships])

    if length(relate) == length(relationships) do
      case invalid_edge_labels =
             Enum.reduce(relate, [], fn {_relationship_name, edge_label, _edge_direction}, acc ->
               if Regex.match?(@regex, Atom.to_string(edge_label)) do
                 acc
               else
                 [to_string(edge_label) | acc]
               end
             end) do
        [] ->
          relationships = Verifier.get_entities(dsl, [:relationships])
          relationship_names = Enum.into(relationships, [], &Map.get(&1, :name))

          case mismatched_relationship_names =
                 Enum.reduce(relate, [], fn {relationship_name, _edge_label, _edge_direction}, acc ->
                   if relationship_name in relationship_names do
                     acc
                   else
                     [to_string(relationship_name) | acc]
                   end
                 end) do
            [] ->
              case invalid_edge_directions =
                     Enum.reduce(relate, [], fn {_relationship_name, _edge_label, edge_direction}, acc ->
                       if edge_direction in [:incoming, :outgoing] do
                         acc
                       else
                         [to_string(edge_direction) | acc]
                       end
                     end) do
                [] ->
                  :ok

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
         message: "relate: relate must have an entry for each relationship"
       )}
    end
  end
end
