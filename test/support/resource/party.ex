# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Resource.Party do
  @moduledoc false
  # A source that reaches a Place via a PlaceRef joiner: Party -> PlaceRef -> Place.
  use Ash.Resource,
    domain: AshNeo4j.Test.SRM,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    label :Party
    relate [{:place_ref, :HAS_PLACE_REF, :outgoing, :PlaceRef}]
    skip [:place_ref_id]
  end

  actions do
    default_accept :*
    defaults [:read, :destroy]

    create :create do
      primary? true
      argument :via_place_ref, :uuid
      change manage_relationship(:via_place_ref, :place_ref, type: :append_and_remove)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :place_ref_id, :uuid
  end

  relationships do
    belongs_to :place_ref, AshNeo4j.Test.Resource.PlaceRef, public?: true
  end
end
