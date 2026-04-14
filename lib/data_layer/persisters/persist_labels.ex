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
    domain_label = short_name(domain_module) |> to_pascal_case()

    resource_module = Verifier.get_persisted(dsl, :module)
    default_resource_label = short_name(resource_module) |> to_pascal_case()
    resource_label = Transformer.get_option(dsl, [:neo4j], :label, default_resource_label)

    {:ok,
     dsl
     |> Transformer.persist(:domain_label, domain_label)
     |> Transformer.persist(:label, resource_label)
     |> Transformer.persist(:labels, [domain_label, resource_label])}
  end
end
