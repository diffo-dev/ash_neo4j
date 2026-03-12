# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Resource.Resource do
  @moduledoc false
  use Ash.Resource,
    domain: AshNeo4j.Test.Domain,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    relate [
      {:specification, :SPECIFIES, :incoming, :Specification},
      {:service, :CONFIGURES, :incoming, :Service},
      {:resource, :USES, :incoming, :Resource},
      {:resources, :USES, :outgoing, :Resource},
      {:event, :FIRED, :outgoing, :Event}
    ]
  end

  actions do
    defaults [:destroy]

    read :read do
      primary? true
    end

    create :create do
      primary? true
      accept [:name]
      argument :specified_by, :uuid
      argument :used_by_service, :uuid
      argument :fire_event, :uuid

      change manage_relationship(:specified_by, :specification, type: :append_and_remove)
      change manage_relationship(:used_by_service, :service, type: :append_and_remove)
      change manage_relationship(:fire_event, :event, type: :append_and_remove)
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:state, :status]
      argument :specified_by, :uuid
      argument :use_resources, {:array, :uuid}
      argument :fire_event, :uuid

      change manage_relationship(:specified_by, :specification, type: :append_and_remove)
      change manage_relationship(:use_resources, :resources, type: :append_and_remove)
      change manage_relationship(:fire_event, :event, type: :append_and_remove)
    end
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :name, :string, public?: true
    attribute :state, :atom, public?: true
    attribute :status, :atom, public?: true
    attribute :service_id, :uuid, public?: true
    attribute :resource_id, :uuid, public?: true
  end

  relationships do
    belongs_to :specification, AshNeo4j.Test.Resource.Specification, public?: true
    belongs_to :service, AshNeo4j.Test.Resource.Service, public?: true
    belongs_to :resource, AshNeo4j.Test.Resource.Resource, public?: true
    has_many :resources, AshNeo4j.Test.Resource.Resource
    has_one :event, AshNeo4j.Test.Resource.Event
  end
end
