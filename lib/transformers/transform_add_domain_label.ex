# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Transformers.TransformAddDomainLabel do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer
  alias Spark.Dsl.Verifier
  import AshNeo4j.Util

  @impl true
  def transform(dsl) do
    {:ok, add_domain_label(dsl)}
  end

  defp add_domain_label(dsl) do
    domain_module = Verifier.get_persisted(dsl, [:env], :domain)
    domain_label = short_name(domain_module) |> to_pascal_case()

    Transformer.set_option(dsl, [:neo4j], :domain_label, domain_label)
  end
end
