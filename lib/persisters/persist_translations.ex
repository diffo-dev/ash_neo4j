# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Persisters.PersistTranslations do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer
  alias Spark.Dsl.Verifier
  import AshNeo4j.Util

  @impl true
  def transform(dsl) do
    transformed_dsl =
      dsl
      |> add_translations()
      |> ensure_id_translated()

    {:ok, transformed_dsl}
  end

  defp add_translations(dsl) do
    # collect source attributes from 1:1 belongs_to relationships to avoid translating them
    source_attributes =
      Verifier.get_entities(dsl, [:relationships])
      |> Enum.reduce([], fn relationship, acc ->
        case relationship do
          %{source_attribute: source_attribute, type: :belongs_to, cardinality: :one}
          when not is_nil(source_attribute) ->
            [source_attribute | acc]

          _ ->
            acc
        end
      end)

    translations =
      Verifier.get_entities(dsl, [:attributes])
      |> Enum.into([], fn attribute ->
        source = Map.get(attribute, :source)

        if source == attribute.name || source == nil do
          {attribute.name, to_camel_case(attribute.name)}
        else
          {attribute.name, source}
        end
      end)
      |> Enum.reject(fn {name, _} -> name in source_attributes end)
      |> Enum.reject(fn {name, _} -> name in Verifier.get_option(dsl, [:neo4j], :skip, []) end)

    Transformer.persist(dsl, :translations, translations)
  end

  defp ensure_id_translated(dsl) do
    translations = Verifier.get_persisted(dsl, :translations, [])

    if Keyword.get(translations, :id) == :id do
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
        transformation = translations |> Keyword.put(:id, to_camel_case(short_type))
        Transformer.persist(dsl, :translations, transformation)
      else
        dsl
      end
    else
      dsl
    end
  end
end
