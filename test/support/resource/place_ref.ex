# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Resource.PlaceRef do
  @moduledoc false
  # A joiner node connecting a source to a Place (diffo's PlaceRef shape). The
  # connection's meaning lives on the node — AshNeo4j has no edge properties.
  use Ash.Resource,
    domain: AshNeo4j.Test.SRM,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    label :PlaceRef
    relate [{:place, :REFERS_TO, :outgoing, :Place}]
    skip [:place_id]
  end

  actions do
    default_accept :*
    defaults [:read, :destroy]

    create :create do
      primary? true
      argument :refers_to, :uuid
      change manage_relationship(:refers_to, :place, type: :append_and_remove)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :role, :string, public?: true
    attribute :place_id, :uuid
  end

  relationships do
    belongs_to :place, AshNeo4j.Test.Resource.Place, public?: true
  end
end
