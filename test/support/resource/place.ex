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
    attribute :location, AshNeo4j.Type.Point, public?: true
    attribute :bounds, AshNeo4j.Type.Box, public?: true
    attribute :path, AshNeo4j.Type.LineString, public?: true
  end
end
