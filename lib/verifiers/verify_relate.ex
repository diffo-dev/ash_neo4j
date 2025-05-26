defmodule AshNeo4j.Verifiers.VerifyRelate do
  @moduledoc "Verifies that a relate relates to a relationship, and that the edge label meets Neo4j conventions"
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError
  @regex ~r/^[A-Z]*_?[A-Z]*$/

  @impl true
  def verify(dsl) do
    resource = Verifier.get_persisted(dsl, :module)
    relate = Verifier.get_option(dsl, [:neo4j], :relate, nil)
    cond do
      relate == nil ->
        :ok

        true ->
          if !Enum.all?(relate, fn {_relationship_name, edge_label, _edge_direction} ->
              Regex.match?(@regex, Atom.to_string(edge_label)) end) do
            {:error,
            DslError.exception(
              module: resource,
              message: "edge label must be upper case and may have an underscore"
            )}
          else
            relationships = Verifier.get_entities(dsl, [:relationships])
            relationship_names = Enum.into(relationships, [], &Map.get(&1, :name))
            if Enum.any?(relate, fn {relationship_name, _edge_label, _edge_direction} ->
                relationship_name not in relationship_names end) do
                  {:error,
                  DslError.exception(
                    module: resource,
                    message: "relate relationship_name must match the name of a relationship"
                  )}
            else
              :ok
            end
          end
    end
  end
end
