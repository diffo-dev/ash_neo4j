# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.DataLayer.Domain.PersistFragmentLabel do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  @impl true
  def transform(dsl) do
    fragment_label = Transformer.get_option(dsl, [:neo4j], :label)
    {:ok, Transformer.persist(dsl, :neo4j_domain_label, fragment_label)}
  end
end

defmodule AshNeo4j.DataLayer.Domain do
  @moduledoc """
  Domain-level DSL extension for AshNeo4j.

  Attach to an Ash domain (directly or via a domain fragment) to write an additional
  label on every node in that domain.

      defmodule Telco do
        use Spark.Dsl.Fragment,
          of: Ash.Domain,
          extensions: [AshNeo4j.DataLayer.Domain]

        neo4j do
          label :Telco
        end
      end

      defmodule Provider do
        use Ash.Domain, fragments: [Telco]
      end

  Nodes for resources in `Provider` will have `:Telco` written as an additional
  label on CREATE, giving the graph a semantically navigable axis.
  """

  @neo4j %Spark.Dsl.Section{
    name: :neo4j,
    schema: [
      label: [
        type: :atom,
        doc: "Label written on CREATE for all nodes whose resource belongs to this domain.",
        required: false
      ]
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@neo4j],
    transformers: [AshNeo4j.DataLayer.Domain.PersistFragmentLabel]
end
