# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Persisters.PersistMapping do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer
  alias Spark.Dsl.Verifier
  alias AshNeo4j.{EdgeDescriptor, ResourceMapping}

  @impl true
  def after?(AshNeo4j.Persisters.PersistLabels), do: true
  def after?(AshNeo4j.Persisters.PersistTranslations), do: true
  def after?(AshNeo4j.Persisters.PersistRelationshipAttributes), do: true
  def after?(AshNeo4j.Persisters.PersistRelate), do: true
  def after?(_), do: false

  @impl true
  def transform(dsl) do
    resource = Verifier.get_persisted(dsl, :module)
    domain_label = Verifier.get_persisted(dsl, :domain_label)
    module_label = Verifier.get_persisted(dsl, :module_label)
    label = Verifier.get_persisted(dsl, :label)
    domain_fragment_label = Verifier.get_persisted(dsl, :domain_fragment_label)
    all_labels = Verifier.get_persisted(dsl, :all_labels, [])
    label_pair = Verifier.get_persisted(dsl, :label_pair, [])
    properties = Verifier.get_persisted(dsl, :translations, [])
    relate = Verifier.get_persisted(dsl, :relate, [])
    relationship_attributes = Verifier.get_persisted(dsl, :relationship_attributes, [])
    guards = Transformer.get_option(dsl, [:neo4j], :guard, [])
    skip = Transformer.get_option(dsl, [:neo4j], :skip, [])

    mapping = %ResourceMapping{
      module: resource,
      domain_label: domain_label,
      module_label: module_label,
      label: label,
      domain_fragment_label: domain_fragment_label,
      all_labels: all_labels,
      label_pair: label_pair,
      properties: properties,
      edges: Enum.map(relate, &EdgeDescriptor.from_relate/1),
      relationship_attributes: relationship_attributes,
      guards: guards,
      skip: skip
    }

    {:ok,
     Transformer.eval(
       dsl,
       [],
       quote do
         @doc false
         def __ash_neo4j_mapping__, do: unquote(Macro.escape(mapping))
       end
     )}
  end
end
