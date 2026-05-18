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

    domain_fragment_label =
      if Code.ensure_loaded?(domain_module) and
           function_exported?(domain_module, :spark_dsl_config, 0) do
        case AshNeo4j.DataLayer.Domain.Info.neo4j_label(domain_module) do
          {:ok, label} -> label
          :error -> nil
        end
      end

    # module_label is always the short name of the resource module itself (:Shelf).
    # resource_label may differ when a fragment contributes a base type label (e.g. :Instance from BaseInstance).
    # domain_fragment_label comes from a domain fragment using AshNeo4j.DataLayer.Domain.
    # all_labels: written on CREATE (up to 4 labels).
    # label_pair: [domain_label, module_label] — used for MATCH on read, update, delete.
    all_labels =
      [domain_label | Enum.uniq([module_label, resource_label])]
      |> then(fn ls -> if domain_fragment_label, do: ls ++ [domain_fragment_label], else: ls end)

    label_pair = [domain_label, module_label]

    {:ok,
     dsl
     |> Transformer.persist(:domain_label, domain_label)
     |> Transformer.persist(:module_label, module_label)
     |> Transformer.persist(:label, resource_label)
     |> Transformer.persist(:domain_fragment_label, domain_fragment_label)
     |> Transformer.persist(:all_labels, all_labels)
     |> Transformer.persist(:label_pair, label_pair)}
  end
end
