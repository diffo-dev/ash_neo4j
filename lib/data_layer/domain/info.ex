# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.DataLayer.Domain.Info do
  @moduledoc "Introspection helpers for AshNeo4j.DataLayer.Domain"

  alias Spark.Dsl.Extension

  @doc """
  Returns the label declared in the domain's `neo4j do` block.

  The label is written on CREATE for every node whose resource belongs
  to this domain. It provides an additional axis for graph traversal
  independent of the specific resource type.

  Returns `nil` if the domain does not use `AshNeo4j.DataLayer.Domain` or
  declares no label.
  """
  @spec label(Ash.Domain.t()) :: atom() | nil
  def label(domain) do
    Extension.get_opt(domain, [:neo4j], :label, nil, true)
  end
end
