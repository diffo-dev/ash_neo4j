# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Calculations.ProjectedTraversal do
  @moduledoc """
  Read-time projection of a graph traversal (#329): follows a hop `chain` from
  each record to the reached node and returns it as a value — late-binding the
  reached node's concrete type at read time via `AshNeo4j.worlds/1`.

  Use it where the reached node's concrete subtype isn't known at the source
  resource's compile time (open-world refs across a cascade) — the read-time
  sibling of the `traverse(^chain, …)` filter expression.

  ## Usage

      calculate :site, :struct,
        {AshNeo4j.Calculations.ProjectedTraversal,
         chain: [{:forward, :place_ref}, {:forward, :place}]}

  ## Options

    * `:chain` (required) — the hop chain, each hop `{:forward | :reverse,
      edge_selector}`, same grammar as the `traverse/2` expression.

  ## Result per record

    * the **concrete record** — a node was reached and its labels resolved to a
      loaded `(domain, resource)` world;
    * `%AshNeo4j.Unknown{reason: :no_concrete_world}` — a node was reached but
      its labels resolve to no loaded world (it can't be returned as a typed
      record);
    * `nil` — nothing was reached (genuine absence);
    * `%Ash.NotLoaded{}` — until the calculation is loaded.

  v1 is single-valued (the first reached node) and projects the reached record;
  list projection and single-field projection are follow-ups.
  """
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: []

  @impl true
  def calculate([], _opts, _context), do: []

  def calculate(records, opts, _context) do
    chain = Keyword.fetch!(opts, :chain)
    resource = hd(records).__struct__
    pk_field = hd(Ash.Resource.Info.primary_key(resource))
    by_source = AshNeo4j.DataLayer.project_traversal(resource, records, chain)

    Enum.map(records, fn record -> Map.get(by_source, Map.get(record, pk_field)) end)
  end
end
