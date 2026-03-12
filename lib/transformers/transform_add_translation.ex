# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Transformers.TransformAddTranslation do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer
  alias Spark.Dsl.Verifier
  import AshNeo4j.Util

  @impl true
  def transform(dsl) do
    {:ok, add_translation(dsl)}
  end

  @impl true
  def after?(AshStateMachine.Transformers.AddState), do: true
  def after?(_), do: false

  defp add_translation(dsl) do
    # collect source attributes from 1:1 belongs_to relationships to avoid translating them
    source_attributes =
      Verifier.get_entities(dsl, [:relationships])
      |> Enum.reduce([], fn relationship, acc ->
        case relationship do
          %{source_attribute: source_attribute, type: :belongs_to, cardinality: :one} when not is_nil(source_attribute) ->
            [source_attribute | acc]

          _ ->
            acc
        end
      end)

    translation =
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

    Transformer.set_option(dsl, [:neo4j], :translation, translation)
  end
end
