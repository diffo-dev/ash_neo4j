# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Type.LocatedDogTypedStruct do
  @moduledoc """
  A TypedStruct with a nested Geo field. Used by tests for #274's
  recursive geo-promotion — when an attribute typed with this lives on
  a resource, the data layer walks the dumped value for nested
  `%Geo.*{}` structs and promotes their indexable companions to the
  node at the dotted path (`<attr>.home.point` for the home field).

  The canonical GeoJSON for `home` lives inside the parent's JSON blob
  (via `Util.to_json_safe`'s Geo handling); the indexable sidecar at
  the node level is for `point.distance` / `point.withinBBox` pushdown.
  """
  use Ash.TypedStruct

  typed_struct do
    field :name, :string, allow_nil?: false
    field :breed, :atom, default: nil
    field :home, AshGeo.GeoJson, constraints: [geo_types: [:point], force_srid: 4326]
  end
end
