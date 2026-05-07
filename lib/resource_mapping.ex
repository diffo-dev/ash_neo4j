# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.ResourceMapping do
  @moduledoc """
  A compile-time description of how an Ash resource maps to the Neo4j graph.

  `ResourceMapping` is the single source of truth for the graph shape of a resource. It is built
  from persisted DSL state via `AshNeo4j.Resource.Info.mapping/1` and collects every piece of
  information the data layer needs without requiring scattered calls to individual `Resource.Info`
  accessors.

  ## Fields

  - `:module` — the Ash resource module (e.g. `DiffoExample.Access.Shelf`).
  - `:domain_label` — PascalCase short name of the domain module, written on CREATE
    (e.g. `:Access`).
  - `:module_label` — PascalCase short name of the resource module itself, always the resource's
    own name regardless of any fragment override (e.g. `:Shelf`).
  - `:label` — the label used in MATCH for reads, updates, and deletes; comes from the DSL
    `label` option and may be a fragment base-type label (e.g. `:Instance` when `Shelf` extends
    `BaseInstance`).
  - `:labels` — full ordered list of labels written on CREATE: `[domain_label, module_label, ...]`
    including any additional base-type labels from fragments (e.g. `[:Access, :Shelf, :Instance]`).
  - `:properties` — keyword list of `{ash_attribute_name, neo4j_property_name}` translations;
    insertion order is preserved.
  - `:edges` — list of `AshNeo4j.EdgeDescriptor.t()` structs, one per `relate` entry.
  - `:relationship_attributes` — keyword list of `{source_attribute, relationship_name}` pairs for
    attributes that hold foreign keys; used to create edges during CREATE.
  - `:guards` — list of `{edge_label, direction, destination_label}` tuples that block deletion.
  - `:skip` — list of relationship names excluded from automatic edge management.
  """

  alias AshNeo4j.EdgeDescriptor

  @type t :: %__MODULE__{
          module: atom(),
          domain_label: atom(),
          module_label: atom(),
          label: atom(),
          labels: [atom()],
          properties: keyword(String.t()),
          edges: [EdgeDescriptor.t()],
          relationship_attributes: keyword(atom()),
          guards: list(tuple()),
          skip: [atom()]
        }

  defstruct [
    :module,
    :domain_label,
    :module_label,
    :label,
    :labels,
    :properties,
    :edges,
    :relationship_attributes,
    :guards,
    :skip
  ]
end
