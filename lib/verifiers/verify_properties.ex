defmodule AshNeo4j.Verifiers.VerifyProperties do
  @moduledoc "Verifies that Neo4j properties follow conventions"
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError
  @regex ~r/^[a-zA-Z][a-zA-Z0-9_]*$/

  @impl true
  def verify(dsl) do
    resource = Verifier.get_persisted(dsl, :module)
    store = Verifier.get_option(dsl, [:neo4j], :store, [])
    translate = Verifier.get_option(dsl, [:neo4j], :translate, [])
    property_names = store ++ Keyword.values(translate) |> IO.inspect(label: :property_names)
    cond do
      property_names == [] ->
        :ok

      true ->
        if !Enum.all?(property_names, &Regex.match?(@regex, Atom.to_string(&1))) do
          {:error,
          DslError.exception(
            module: resource,
            message: "neo4j property names should start with a letter and may contain numbers and underscores, use translate"
          )}
        else
          :ok
        end
    end
  end
end
