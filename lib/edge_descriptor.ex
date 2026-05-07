# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.EdgeDescriptor do
  @moduledoc """
  Describes a single graph edge from a resource's perspective.

  An `EdgeDescriptor` captures the graph-level facts about one entry in a resource's `relate`
  DSL block: the edge label, the direction it travels from the source node, and the label of the
  node at the other end. It does **not** reference a destination Ash resource module — that would
  require the destination to be compiled, and edges can point to nodes whose resource hasn't been
  written yet.

  ## Fields

  - `:relationship` — the Ash relationship name declared on the source resource (e.g. `:shelves`).
    `nil` when the descriptor is built from raw edge data rather than a `relate` tuple.
  - `:label` — the Neo4j edge type label (e.g. `:HAS_SHELF`).
  - `:direction` — `:outgoing` if the edge goes *from* the source node, `:incoming` if it arrives
    *at* the source node.
  - `:destination_label` — the Neo4j node label matched at the far end (e.g. `:Shelf`).

  Build a list of these from a resource via `AshNeo4j.Resource.Info.mapping/1`, which returns a
  `%AshNeo4j.ResourceMapping{}` whose `:edges` field holds `[EdgeDescriptor.t()]`.
  """

  @type t :: %__MODULE__{
          relationship: atom() | nil,
          label: atom(),
          direction: :incoming | :outgoing,
          destination_label: atom()
        }

  defstruct [:relationship, :label, :direction, :destination_label]

  @doc "Build an EdgeDescriptor from a relate tuple {name, label, direction, dest_label}"
  def from_relate({name, label, direction, destination_label}) do
    %__MODULE__{
      relationship: name,
      label: label,
      direction: direction,
      destination_label: destination_label
    }
  end
end
