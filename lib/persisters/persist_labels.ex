# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Persisters.PersistLabels do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer
  alias Spark.Dsl.Verifier
  import AshNeo4j.Util

  @impl true
  def transform(dsl) do
    domain_module = Verifier.get_persisted(dsl, :domain, :Domain)
    domain_label = short_name(domain_module)

    resource_module = Verifier.get_persisted(dsl, :module)
    module_label = short_name(resource_module)
    resource_label = Transformer.get_option(dsl, [:neo4j], :label, module_label)

    # module_label is always the short name of the resource module itself (:Shelf).
    # resource_label may differ when a fragment contributes a base type label (e.g. :Instance from BaseInstance).
    # Both are written on CREATE so polymorphic traversals work; reads match on resource_label only.
    labels = [domain_label | Enum.uniq([module_label, resource_label])]

    {:ok,
     dsl
     |> Transformer.persist(:domain_label, domain_label)
     |> Transformer.persist(:module_label, module_label)
     |> Transformer.persist(:label, resource_label)
     |> Transformer.persist(:labels, labels)}
  end
end
