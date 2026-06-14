# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Error.RequiresCypher25 do
  @moduledoc """
  Returned (never raised) when a Cypher 25 operation is attempted against a Neo4j
  server older than 2025.06. Upgrade to Neo4j 2025.06 or later to use this feature.
  """
  use Splode.Error, fields: [], class: :invalid

  def message(_), do: "This operation requires Cypher 25 (Neo4j ≥ 2025.06)"
end

defmodule AshNeo4j.Error.GeoDimensionMismatch do
  @moduledoc """
  Returned (never raised) when a spatial operation combines geometries of
  different coordinate dimensions (2D vs 3D) — e.g. a 3D `%Geo.PointZ{}` against
  a 2D attribute, or vice versa. Neo4j silently returns `null` for mixed-CRS
  operations (which then drops rows in a `WHERE`), so AshNeo4j refuses up front
  (#270) by returning `{:error, error}`.

  Bridge worlds explicitly with a downward projection
  (`AshNeo4j.Geo.force_2d/1`) — collapse the 3D operand to its 2D footprint
  and evaluate in 2D. There is no implicit 2D→3D lift (a height cannot be
  fabricated).
  """
  use Splode.Error, fields: [:attr_dim, :value_dim], class: :invalid

  def message(%{attr_dim: attr_dim, value_dim: value_dim}) do
    "spatial dimension mismatch: a #{value_dim}D value against a #{attr_dim}D attribute. " <>
      "Project the 3D operand to 2D with AshNeo4j.Geo.force_2d/1 to evaluate in the 2D world, " <>
      "or use genuinely matching dimensions."
  end
end

defmodule AshNeo4j.Error.Unsupported3DGeometry do
  @moduledoc """
  Returned (never raised) when a 3D areal or linear geometry (`%Geo.PolygonZ{}`,
  `%Geo.LineStringZ{}`, …) is written. #270 Phase 1 supports 3D **points**
  (`%Geo.PointZ{}`) only; 3D areal/linear geometries are deferred to Phase 2,
  because exact 3D containment/distance needs a model the 2D `topo` refinement
  cannot provide. Storing 2D bbox companions would silently drop the z.
  """
  use Splode.Error, fields: [:geometry], class: :invalid

  def message(%{geometry: geometry}) do
    "#{inspect(geometry)} (3D areal/linear geometry) is not supported yet — #270 Phase 1 covers " <>
      "Geo.PointZ only. Use a 2D geometry, or project to 2D, until 3D areal support lands."
  end
end

defmodule AshNeo4j.Error.UnresolvableTraversal do
  @moduledoc """
  **Returned** (never raised) when a `traverse(^chain, …)` filter predicate can't
  be formed because the current graph view can't resolve part of it — a reached
  node whose label resolves to no loaded resource, or a field that isn't a
  mapped property of the reached resource.

  The filter-context counterpart to `AshNeo4j.Unknown` (the value-context
  "couldn't determine"): same `{world, reason, context}` shape. A data layer
  returns this as `{:error, error}` and never raises — `:reason` is a structural
  atom, `:context` is diagnostic.
  """
  use Splode.Error, fields: [:world, :reason, :context], class: :invalid

  def message(%{world: world, reason: reason, context: context}) do
    base = "cannot push down a traverse filter on #{inspect(world)} — #{reason}"
    if context in [nil, %{}], do: base, else: base <> " (#{inspect(context)})"
  end
end

