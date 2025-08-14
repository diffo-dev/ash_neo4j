defmodule AshNeo4j.Transformers.TransformAddTranslation do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer
  alias Spark.Dsl.Verifier

  @impl true
  def transform(dsl) do
    {:ok, add_translation(dsl)}
  end

  @impl true
  def after?(AshStateMachine.Transformers.AddState), do: true
  def after?(_), do: false

  defp add_translation(dsl) do
    source_attributes =
      Verifier.get_entities(dsl, [:relationships])
      |> Enum.into([], &Map.get(&1, :source_attribute))

    attributes =
      Verifier.get_entities(dsl, [:attributes])
      |> Enum.into([], &Map.get(&1, :name))
      |> Enum.reject(fn name -> name in source_attributes end)
      |> Enum.reject(fn name -> name in Verifier.get_option(dsl, [:neo4j], :skip, []) end)

    translate = Verifier.get_option(dsl, [:neo4j], :translate, [])
    direct = Enum.into(attributes, [], fn attribute -> {attribute, camelCase(attribute)} end)
    translation = Keyword.merge(direct, translate)
    Transformer.set_option(dsl, [:neo4j], :translation, translation)
  end

  defp camelCase(atom) when is_atom(atom) do
    splits = String.split(Atom.to_string(atom), "_")
    (hd(splits) <> Enum.map_join(tl(splits), "", fn s -> String.capitalize(s) end)) |> String.to_atom()
  end
end
