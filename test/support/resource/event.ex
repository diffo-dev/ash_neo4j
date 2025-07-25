defmodule AshNeo4j.Test.Resource.Event do
  @moduledoc false
  use Ash.Resource,
    domain: AshNeo4j.Test.Domain,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    label :Event

    relate [
      {:previous_event, :AFTER, :outgoing},
      {:service, :FIRED, :incoming},
      {:resource, :FIRED, :incoming}
    ]

    translate id: :uuid
    skip([:service_id, :resource_id, :event_id])
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

      argument :previous_event, :uuid
      change manage_relationship(:previous_event, :previous_event, type: :append_and_remove)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :type, :atom, public?: true
    attribute :service_id, :uuid
    attribute :resource_id, :uuid
    attribute :event_id, :uuid, public?: true
  end

  relationships do
    has_one :previous_event, AshNeo4j.Test.Resource.Event, public?: true
    belongs_to :service, AshNeo4j.Test.Resource.Service, public?: true
    belongs_to :resource, AshNeo4j.Test.Resource.Resource, public?: true
  end

  preparations do
    prepare build(
      load: [:previous_event]
    )
  end

end
