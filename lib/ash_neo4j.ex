# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j do
  @moduledoc """
  Top-level helpers for the AshNeo4j data layer.

  ## N-world projection (`worlds/1`)

  > #### Exploratory (#273) {: .warning}
  >
  > `worlds/1` is a pre-1.0 exploration to unblock cross-domain late
  > binding in downstream consumers ([diffo#172](https://github.com/diffo-dev/diffo/issues/172)).
  > Its shape may change before 1.0 — feedback from real use is the point.
  """

  alias AshNeo4j.Resource.Info, as: ResourceInfo

  @typedoc "A `(domain, resource)` world the node participates in."
  @type world :: {domain :: module(), resource :: module()}

  @doc """
  The `(domain, resource)` worlds a node participates in, **outermost-first**.

  An Ash read returns a struct of the queried resource type — the "base
  world." But a Neo4j node carries labels for *every* `(Domain, Resource)`
  world it participates in (the data layer records them on the read
  struct's `__metadata__.labels`). A polymorphic node typically belongs to
  several. An **outer** world contains the inner worlds and introduces new
  aspects, so it carries more labels — the more labels, the more nuanced
  (more outer) the world. `worlds/1` projects the node's labels back to the
  loadable resource modules, **outermost-first**, so a consumer can recover
  the outer type(s) without reaching into AshNeo4j internals or dropping to
  Cypher.

      record = Ash.get!(SomeBaseInstance, id)
      AshNeo4j.worlds(record)
      #=> [{MyApp, MyApp.ConcreteInstance}, {Diffo.Provider, Diffo.Provider.Instance}]

      # Consumers typically want the outermost (most-nuanced) world:
      {domain, resource} = hd(AshNeo4j.worlds(record))

  ## Resolution

  Resolution is **dynamic against whatever modules are loaded** — no
  registry. A candidate is a loaded resource using `AshNeo4j.DataLayer`
  whose own labels (`AshNeo4j.Resource.Info.all_labels/1`) are a subset of
  the node's labels. Candidates are grouped by domain; the **outermost** —
  the most-nuanced world, the one carrying the most labels — is kept per
  domain, and the result is sorted outermost-first across domains. Outer
  worlds carve known structure out of the node; what can't be resolved to a
  loaded module is left **unknown** — omitted, never coerced into a known
  world. The metadata describes the node, not the caller.

  Returns `[]` for a record without AshNeo4j read metadata (e.g. one not
  produced by this data layer).

  > #### Cost {: .info}
  >
  > Lazy and uncached. Nothing on the read path calls this — it runs only
  > when you call `worlds/1`, and each call scans the loaded modules for
  > AshNeo4j resources and subset-checks their labels. Not a hot path by
  > construction; if real use shows otherwise, a supervised ETS index is the
  > follow-up.
  """
  # Total over any term: a read record (or a synthetic `%{__metadata__: %{labels:
  # …}}` map in tests) resolves; anything else yields `[]`.
  @spec worlds(term()) :: [world()]
  def worlds(record)

  def worlds(%{__metadata__: %{labels: labels}}) when is_list(labels) do
    node_labels = to_label_set(labels)

    ashneo4j_resources()
    |> Enum.filter(fn {label_set, _resource} ->
      not Enum.empty?(label_set) and MapSet.subset?(label_set, node_labels)
    end)
    |> Enum.group_by(fn {_label_set, resource} -> Ash.Resource.Info.domain(resource) end)
    |> Enum.map(fn {domain, candidates} ->
      # Outermost = most nuanced = the world carrying the most labels.
      {label_set, resource} = Enum.max_by(candidates, fn {ls, _} -> MapSet.size(ls) end)
      {MapSet.size(label_set), {domain, resource}}
    end)
    |> Enum.sort_by(&elem(&1, 0), :desc)
    |> Enum.map(&elem(&1, 1))
  end

  def worlds(_record), do: []

  # Node labels arrive as strings ("SRM"); resource labels are atoms (:SRM).
  # A label with no existing atom can't match any loaded resource, so we drop
  # it rather than mint a new atom.
  defp to_label_set(labels) do
    labels
    |> Enum.flat_map(fn
      label when is_atom(label) ->
        [label]

      label when is_binary(label) ->
        try do
          [String.to_existing_atom(label)]
        rescue
          ArgumentError -> []
        end
    end)
    |> MapSet.new()
  end

  # `{label_set, resource}` for every loaded resource using AshNeo4j.DataLayer.
  # Scanned fresh each call — no cache, no global state. worlds/1 is
  # consumer-invoked (never on the read path), so this isn't hot, and a fresh
  # scan reflects exactly what's loaded right now.
  defp ashneo4j_resources do
    :code.all_loaded()
    |> Enum.map(&elem(&1, 0))
    |> Enum.filter(&ashneo4j_resource?/1)
    |> Enum.map(fn resource -> {MapSet.new(ResourceInfo.all_labels(resource)), resource} end)
  end

  defp ashneo4j_resource?(module) do
    Ash.Resource.Info.resource?(module) and Ash.DataLayer.data_layer(module) == AshNeo4j.DataLayer
  rescue
    _ -> false
  end
end
