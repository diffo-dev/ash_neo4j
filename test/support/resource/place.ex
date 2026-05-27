# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Resource.Place do
  @moduledoc false
  use Ash.Resource,
    domain: AshNeo4j.Test.SRM,
    data_layer: AshNeo4j.DataLayer

  actions do
    default_accept :*
    defaults [:read, :create, :destroy]
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true

    attribute :location, AshGeo.GeoJson,
      public?: true,
      constraints: [geo_types: [:point], force_srid: 4326]

    attribute :bounds, AshGeo.GeoJson,
      public?: true,
      constraints: [geo_types: [:polygon], force_srid: 4326]

    attribute :path, AshGeo.GeoJson,
      public?: true,
      constraints: [geo_types: [:line_string], force_srid: 4326]

    attribute :pes, AshGeo.GeoJson,
      public?: true,
      constraints: [geo_types: [:multi_point], force_srid: 4326]

    attribute :regions, AshGeo.GeoJson,
      public?: true,
      constraints: [geo_types: [:multi_polygon], force_srid: 4326]

    # #279 #5 — MultiLineString round-trips and works with the predicates
    # by construction (Util handles it, topo supports it); this attribute
    # gives the tests something concrete to assert against.
    attribute :routes, AshGeo.GeoJson,
      public?: true,
      constraints: [geo_types: [:multi_line_string], force_srid: 4326]

    # Test fixture for #274's recursive geo-promotion: a TypedStruct
    # with a nested Geo field. The whole struct stores as JSON at
    # <attr>; the nested home Point's indexable companion gets
    # promoted to <attr>.home.point on the node.
    attribute :pet, AshNeo4j.Test.Type.LocatedDogTypedStruct, public?: true
  end
end
