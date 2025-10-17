# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Transformers.TransformEnsureIdTranslated do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer
  alias Spark.Dsl.Verifier
  import AshNeo4j.Util

  @impl true
  def transform(dsl) do
    {:ok, ensure_id_translated(dsl)}
  end

  @impl true
  def after?(AshNeo4j.Transformers.TransformAddTranslation), do: true
  def after?(_), do: false

  defp ensure_id_translated(dsl) do
    translate = Verifier.get_option(dsl, [:neo4j], :translate, [])

    if Keyword.get(translate, :id) == nil do
      attributes = Verifier.get_entities(dsl, [:attributes])

      id_attribute =
        Enum.find(
          attributes,
          fn attribute ->
            Map.get(attribute, :name) == :id
          end
        )

      if id_attribute do
        # translate id using 'short' type converted to camelCase neo4j property style
        short_type = String.to_atom(List.last(Module.split(id_attribute.type)))
        translation = Verifier.get_option(dsl, [:neo4j], :translation, [])
        transformation = translation |> Keyword.put(:id, to_camel_case(short_type))
        Transformer.set_option(dsl, [:neo4j], :translation, transformation)
      else
        dsl
      end
    else
      dsl
    end
  end
end
