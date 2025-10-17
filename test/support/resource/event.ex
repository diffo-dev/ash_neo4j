# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Resource.Event do
  @moduledoc false
  use Ash.Resource,
    domain: AshNeo4j.Test.Domain,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    label :Event

    relate [
      {:service, :RAISED, :incoming, :Service},
      {:resource, :FIRED, :incoming, :Resource}
    ]

    translate id: :uuid
    skip [:service_id, :resource_id]
  end

  actions do
    default_accept :*
    defaults [:destroy]

    read :read do
      primary? true
    end

    create :create do
      primary? true
    end

    update :update do
      primary? true
      accept [:type]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :type, :atom, public?: true
    attribute :service_id, :uuid
    attribute :resource_id, :uuid
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :service, AshNeo4j.Test.Resource.Service, public?: true
    belongs_to :resource, AshNeo4j.Test.Resource.Resource, public?: true
  end

  preparations do
    prepare build(sort: [inserted_at: :desc])
  end
end
