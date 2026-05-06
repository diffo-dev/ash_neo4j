# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.DataLayer.Info do
  @moduledoc "Introspection helpers for AshNeo4j.DataLayer"

  alias Spark.Dsl.Extension

  @doc """
  Returns the label DSL of the resource.
  The label is the PascalCase short name of the resource's Elixir Module name by default, but can be overridden by setting the :label option in the DSL. It is used as a Neo4j label for all nodes of the resource.
  """
  @spec label(Ash.Resource.t()) :: atom() | nil
  def label(resource) do
    Extension.get_opt(resource, [:neo4j], :label, nil, true)
  end

  @doc """
  Returns the relate DSL of the resource
  """
  @spec relate(Ash.Resource.t()) :: list(tuple()) | nil
  def relate(resource) do
    Extension.get_opt(resource, [:neo4j], :relate, [], true)
  end

  @doc """
  Returns the guard DSL of the resource
  """
  @spec guard(Ash.Resource.t()) :: list(tuple()) | nil
  def guard(resource) do
    Extension.get_opt(resource, [:neo4j], :guard, [], true)
  end

  @doc """
  Returns the skip DSL of the resource.
  The skip DSL is a list of attribute names which are not translated to node properties, either because they are transient or because they will be stored as relationships rather than properties.
  By default, all attributes which are the source of a 1:1 belongs_to relationship are skipped, but additional attributes can be skipped by setting the :skip option in the DSL.
  """
  @spec skip(Ash.Resource.t()) :: list() | nil
  def skip(resource) do
    Extension.get_opt(resource, [:neo4j], :skip, [], true)
  end
end
