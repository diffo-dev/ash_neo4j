defmodule AshNeo4j.Verifiers.VerifyIdTranslated do
  @moduledoc "Verifies that id attribute is translated"
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl) do
    resource = Verifier.get_persisted(dsl, :module)
    attributes = Verifier.get_entities(dsl, [:attributes])
    attribute_names = Enum.into(attributes, [], fn attribute -> Map.get(attribute, :name) end)
    cond do
      :id not in attribute_names -> :ok
      true ->
        translate = Verifier.get_option(dsl, [:neo4j], :translate, [])
        cond do
          :id in Keyword.keys(translate) -> :ok
          true ->
            {:error,
            DslError.exception(
              module: resource,
              message: ":id attribute must be translated, e.g. translate id: :uuid"
            )}
        end
    end
  end
end
